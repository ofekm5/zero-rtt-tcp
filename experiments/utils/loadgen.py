#!/usr/bin/env python3
"""
Event-driven TCP load generator for 0-RTT stress testing.

Replaces iperf2 as the Client/Server load generator. iperf2's -P N spawns N
OS threads inside one process — at N=25000 (100k connections / 4 ports) that
is 25000 pthreads in a single process, which is not viable at any instance
size (kernel.threads-max, vm.max_map_count, scheduler thrash — see
docs/capacity-model.md and roadmap.md #20 scope item A). This tool opens
every connection as a lightweight asyncio coroutine on one thread, one event
loop, epoll-driven under the hood — connection count scales with available
fds and kernel limits, not with thread count.

Client mode: opens --parallel TCP connections spread round-robin across
--port-count contiguous ports starting at --port, sends --bytes of payload
per connection, then closes. Mirrors the old `iperf -c ... -P N -n 1M`
per-port-fan-out shape closely enough that run_core.sh/measure.sh need no
downstream changes (analyze_metrics.py works from tcpdump captures, not from
this tool's own output).

Server mode: listens on --port-count contiguous ports starting at --port,
drains each connection until EOF, then closes it.

Usage:
    python3 loadgen.py --mode server --port 8080 --port-count 4
    python3 loadgen.py --mode client --host 10.1.2.4 --port 8080 --port-count 4 \
        --parallel 100000 --bytes 1048576
"""

import argparse
import asyncio
import signal
import sys
import time


async def _client_conn(host, port, nbytes, sem, results):
    async with sem:
        try:
            reader, writer = await asyncio.open_connection(host, port)
        except Exception:
            results["fail"] += 1
            return
        try:
            writer.write(b"\x00" * nbytes)
            await writer.drain()
            writer.write_eof()
        except Exception:
            results["fail"] += 1
            return
        else:
            results["ok"] += 1
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass


async def run_client(host, ports, parallel, nbytes, concurrency_limit):
    sem = asyncio.Semaphore(concurrency_limit)
    results = {"ok": 0, "fail": 0}
    tasks = [
        _client_conn(host, ports[i % len(ports)], nbytes, sem, results)
        for i in range(parallel)
    ]
    t0 = time.monotonic()
    await asyncio.gather(*tasks)
    dt = time.monotonic() - t0
    mbps = (results["ok"] * nbytes * 8 / 1e6 / dt) if dt > 0 else 0.0
    print(f"Transfer complete: {results['ok']}/{parallel} connections ok, "
          f"{results['fail']} failed, duration={dt:.3f}s, ~{mbps:.1f} Mbits/sec")
    print(f"Success: {results['ok']}/{parallel}")
    return 0 if results["fail"] == 0 and results["ok"] == parallel else 1


async def _handle_conn(reader, writer, counters):
    total = 0
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            total += len(chunk)
    except Exception:
        pass
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass
        counters["accepted"] += 1
        counters["bytes"] += total


async def _start_servers(ports, counters):
    """Bind and start accepting on every port. Accepting begins immediately
    on return — serve_forever() below is only needed to block, not to accept —
    so tests can call this directly and skip serve_forever()/cancellation
    entirely (avoids a Windows ProactorEventLoop bug where cancelling a
    serve_forever() task can hang; irrelevant on the Linux deployment target,
    but this keeps local test runs on any platform reliable)."""
    def _factory(counters):
        def _cb(reader, writer):
            asyncio.ensure_future(_handle_conn(reader, writer, counters))
        return _cb

    servers = []
    for port in ports:
        srv = await asyncio.start_server(_factory(counters), "0.0.0.0", port)
        servers.append(srv)
    return servers


async def run_server(ports):
    counters = {"accepted": 0, "bytes": 0}
    servers = await _start_servers(ports, counters)

    print(f"Listening on ports {ports}", flush=True)

    def _print_summary(tag):
        print(f"Received {counters['bytes']} bytes across "
              f"{counters['accepted']} connections ({tag})", flush=True)

    async def _report():
        last = 0
        while True:
            await asyncio.sleep(2)
            if counters["accepted"] != last:
                last = counters["accepted"]
                _print_summary("so far")

    # The harness stops this process with SIGTERM/SIGINT at the end of a run
    # (run_core.sh cleanup, matching the old pkill-iperf behavior) — print a
    # final summary on the way out so "Server received data" checks that grep
    # the log for "Received|bytes" still see a line even on a short run.
    stop_event = asyncio.Event()

    def _handle_signal():
        _print_summary("final")
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, _handle_signal)
        except NotImplementedError:
            pass  # Windows dev/testing fallback — production target is Linux

    # asyncio.TaskGroup/except* need Python 3.11+; Amazon Linux 2's stock
    # python3 is 3.7, so stick to gather() (works since 3.7 — matches
    # CLAUDE.md's stated "Python 3.8+" floor for this project).
    reporter = asyncio.ensure_future(_report())
    serve_task = asyncio.ensure_future(
        asyncio.gather(*(s.serve_forever() for s in servers)))
    await stop_event.wait()
    serve_task.cancel()
    reporter.cancel()
    for s in servers:
        s.close()


def _parse_ports(base, count):
    return list(range(base, base + max(count, 1)))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["client", "server"], required=True)
    ap.add_argument("--host", default=None, help="server host (client mode only)")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--port-count", type=int, default=1)
    ap.add_argument("--parallel", type=int, default=100000,
                     help="total connections spread across --port-count ports (client mode)")
    ap.add_argument("--bytes", type=int, default=1024 * 1024,
                     help="payload bytes sent per connection (client mode)")
    ap.add_argument("--concurrency-limit", type=int, default=None,
                     help="cap on simultaneously in-flight connect() attempts "
                          "(default: --parallel, i.e. no throttling)")
    args = ap.parse_args()

    ports = _parse_ports(args.port, args.port_count)

    if args.mode == "server":
        asyncio.run(run_server(ports))
        return 0

    if not args.host:
        print("ERROR: --host is required for --mode client", file=sys.stderr)
        return 2

    limit = args.concurrency_limit or args.parallel
    return asyncio.run(run_client(args.host, ports, args.parallel, args.bytes, limit))


if __name__ == "__main__":
    sys.exit(main())
