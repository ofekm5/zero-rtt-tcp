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

Arrival pacing (--rate) is what makes per-connection latency measurable.
Without it every connection is created in the same event-loop iteration, so
all --parallel SYNs reach the wire effectively at once; each flow's measured
latency then includes queueing behind every other SYN, i.e. it reports the
data plane's SYN service rate rather than the round-trip the 0-RTT spoof
eliminates. --rate spreads the same total connection count over time, which
turns a saturation event into N independent latency samples. --rate 0
restores the old all-at-once burst for deliberate stress runs.

Server mode: listens on --port-count contiguous ports starting at --port,
drains each connection until EOF, then closes it.

Usage:
    python3 loadgen.py --mode server --port 8080 --port-count 4
    python3 loadgen.py --mode client --host 10.1.2.4 --port 8080 --port-count 4 \
        --parallel 100000 --bytes 1024 --rate 2000 --concurrency-limit 2000
"""

import argparse
import asyncio
import signal
import sys
import time


async def _client_conn(host, port, nbytes, sem, results, think=0.0):
    async with sem:
        try:
            reader, writer = await asyncio.open_connection(host, port)
        except Exception:
            results["fail"] += 1
            return
        # Client think time: the pause between connect() returning and the first
        # request being written. Default 0 models an HTTP-style client that
        # sends immediately — the workload 0-RTT targets and the hard case for
        # it. See experiments/measurement-methodology-review.md and the wiki's
        # "Load Generation and Think Time" entry: a non-zero value is a
        # legitimate extra axis only once the emulated WAN sits on the middle
        # leg, never a substitute for fixing the placement.
        if think > 0:
            await asyncio.sleep(think)
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


async def run_client(host, ports, parallel, nbytes, concurrency_limit, rate=0.0,
                     think_ms=0.0):
    """Open `parallel` connections, paced at `rate` connections/sec (0 = burst).

    Pacing schedules connection i for t0 + i/rate on an absolute timeline rather
    than sleeping 1/rate between spawns, so per-sleep overhead cannot accumulate
    into drift over a 100k-connection run. When the loop falls behind schedule
    the delay goes non-positive and the spawn happens immediately — the requested
    rate becomes a ceiling, not a guarantee, which is why the achieved rate is
    reported below: a large gap means the pacing target was unreachable and the
    run degraded toward a burst.
    """
    sem = asyncio.Semaphore(concurrency_limit)
    results = {"ok": 0, "fail": 0}
    tasks = []
    think = think_ms / 1000.0
    t0 = time.monotonic()
    for i in range(parallel):
        if rate > 0:
            delay = (t0 + i / rate) - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)
        tasks.append(asyncio.ensure_future(
            _client_conn(host, ports[i % len(ports)], nbytes, sem, results,
                         think)))
    spawn_end = time.monotonic()
    await asyncio.gather(*tasks)
    dt = time.monotonic() - t0
    spawn_dt = spawn_end - t0
    mbps = (results["ok"] * nbytes * 8 / 1e6 / dt) if dt > 0 else 0.0
    achieved = (parallel / spawn_dt) if spawn_dt > 0 else float("inf")
    pacing = (f"burst (unpaced), achieved {achieved:.0f} conn/s"
              if rate <= 0 else
              f"rate={rate:g} conn/s requested, {achieved:.0f} conn/s achieved "
              f"over {spawn_dt:.3f}s")
    print(f"Arrival: {pacing}")
    # Reported unconditionally so a report can never be read without knowing
    # which think time produced it — a sweep's runs are otherwise identical.
    print(f"Think: {think_ms:g} ms between connect() and first write")
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


def _build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["client", "server"], required=True)
    ap.add_argument("--host", default=None, help="server host (client mode only)")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--port-count", type=int, default=1)
    ap.add_argument("--parallel", type=int, default=100000,
                     help="total connections spread across --port-count ports (client mode)")
    ap.add_argument("--bytes", type=int, default=1024,
                     help="payload bytes sent per connection (client mode). "
                          "Default 1024 = one segment, so flow completion time is "
                          "dominated by the handshake the 0-RTT spoof shortens "
                          "rather than by bulk transfer")
    ap.add_argument("--rate", type=float, default=0.0,
                     help="connection arrival rate in connections/sec (client "
                          "mode). 0 = all at once (burst). Pace arrivals to "
                          "measure per-connection latency; burst to stress-test")
    ap.add_argument("--concurrency-limit", type=int, default=None,
                     help="cap on simultaneously in-flight connect() attempts "
                          "(default: --parallel, i.e. no throttling)")
    ap.add_argument("--think-ms", type=float, default=0.0,
                     help="client think time in ms between connect() returning "
                          "and the first write (client mode). Default 0 models "
                          "an HTTP-style client that sends immediately. Sweep "
                          "it to characterise how much of the 0-RTT gain "
                          "survives a client that does not send immediately")
    return ap


def main():
    args = _build_parser().parse_args()

    ports = _parse_ports(args.port, args.port_count)

    if args.mode == "server":
        asyncio.run(run_server(ports))
        return 0

    if not args.host:
        print("ERROR: --host is required for --mode client", file=sys.stderr)
        return 2

    limit = args.concurrency_limit or args.parallel
    return asyncio.run(run_client(args.host, ports, args.parallel, args.bytes,
                                  limit, args.rate, args.think_ms))


if __name__ == "__main__":
    sys.exit(main())
