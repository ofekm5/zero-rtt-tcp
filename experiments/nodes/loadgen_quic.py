#!/usr/bin/env python3
"""
QUIC load generator (aioquic) — the QUIC cold / QUIC resumed arms of the
four-arm comparison. Same paced-arrival shape as loadgen.py (--rate,
--parallel, --bytes, --port/--port-count); loadgen.py itself is untouched.

The metric is app-side, on the client's own clock, per connection:

  send_unlock_ms       connect start until the first write is permitted:
                       handshake complete when cold; immediately after
                       connect() returns when resuming (0-RTT early data).
  handshake_ms         connect start until handshake complete, always.
  early_data_accepted  whether the server accepted the 0-RTT data (aioquic
                       TLS state) — False means resumption silently fell back
                       to 1-RTT and send_unlock_ms for that flow is a lie.

Every client process first makes one priming cold connection that saves a
session ticket; with --resume every later connection reuses that one ticket.
The priming connection is not part of the reported samples. The server keeps
tickets in memory and hands the same ticket out repeatedly (it never pops).

Usage:
    python3 loadgen_quic.py --mode server --port 8080 --port-count 4 \
        --cert /tmp/quic.crt --key /tmp/quic.key
    python3 loadgen_quic.py --mode client --host 10.1.2.4 --port 8080 \
        --port-count 4 --parallel 1000 --bytes 1024 --rate 200 [--resume]
"""

import argparse
import asyncio
import signal
import ssl
import sys
import time

from aioquic.asyncio import connect, serve
from aioquic.quic.configuration import QuicConfiguration

ALPN = ["loadgen"]
TICKET_WAIT_S = 5.0


def _pct(values, p):
    """Nearest-rank percentile; 0.0 for an empty sample."""
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int(round(p / 100.0 * len(s) + 0.5)) - 1))]


def _client_config(ticket=None):
    # CERT_NONE: the server runs a throwaway self-signed cert on an isolated
    # lab network; this tool measures handshake timing, not authenticity.
    cfg = QuicConfiguration(is_client=True, alpn_protocols=ALPN,
                            verify_mode=ssl.CERT_NONE)
    cfg.session_ticket = ticket
    return cfg


async def _exchange(proto, nbytes):
    """Send nbytes on one stream, then wait for the server to close its side."""
    reader, writer = await proto.create_stream()
    writer.write(b"\x00" * nbytes)
    writer.write_eof()
    return reader


async def _prime(host, port, nbytes):
    """One cold connection; returns the session ticket the server issued."""
    got = asyncio.Event()
    box = []

    def _save(ticket):
        box.append(ticket)
        got.set()

    async with connect(host, port, configuration=_client_config(),
                       session_ticket_handler=_save) as proto:
        reader = await _exchange(proto, nbytes)
        await reader.read()
        try:
            await asyncio.wait_for(got.wait(), TICKET_WAIT_S)
        except asyncio.TimeoutError:
            pass
    return box[0] if box else None


async def _client_conn(host, port, nbytes, ticket, samples, results):
    resume = ticket is not None
    try:
        t0 = time.monotonic()
        # Resuming: connect() returns before the handshake, so the write below
        # goes out as 0-RTT early data in the first flight. Cold: connect()
        # returns once the handshake is complete — the first moment a write is
        # permitted.
        async with connect(host, port, configuration=_client_config(ticket),
                           wait_connected=not resume) as proto:
            unlock = time.monotonic()
            reader = await _exchange(proto, nbytes)
            await proto.wait_connected()  # no-op when cold
            hs = unlock if not resume else time.monotonic()
            early = bool(proto._quic.tls.early_data_accepted)
            await reader.read()
    except Exception:
        results["fail"] += 1
        return
    results["ok"] += 1
    samples.append(((unlock - t0) * 1000.0, (hs - t0) * 1000.0, early))


async def run_client(host, ports, parallel, nbytes, rate=0.0, resume=False):
    """Open `parallel` QUIC connections paced at `rate` conn/s (0 = burst),
    on the same absolute timeline as loadgen.run_client."""
    ticket = await _prime(host, ports[0], nbytes)
    if resume and ticket is None:
        print("ERROR: priming connection got no session ticket; cannot resume",
              file=sys.stderr)
        return 1

    results = {"ok": 0, "fail": 0}
    samples = []
    tasks = []
    t0 = time.monotonic()
    for i in range(parallel):
        if rate > 0:
            delay = (t0 + i / rate) - time.monotonic()
            if delay > 0:
                await asyncio.sleep(delay)
        tasks.append(asyncio.ensure_future(
            _client_conn(host, ports[i % len(ports)], nbytes,
                         ticket if resume else None, samples, results)))
    spawn_dt = time.monotonic() - t0
    await asyncio.gather(*tasks)
    dt = time.monotonic() - t0

    achieved = (parallel / spawn_dt) if spawn_dt > 0 else float("inf")
    print(f"Arrival: rate={rate:g} conn/s requested, {achieved:.0f} conn/s "
          f"achieved over {spawn_dt:.3f}s")
    print(f"Transfer complete: {results['ok']}/{parallel} connections ok, "
          f"{results['fail']} failed, duration={dt:.3f}s")
    print(f"Success: {results['ok']}/{parallel}")
    unlock = [s[0] for s in samples]
    hs = [s[1] for s in samples]
    n = len(samples)
    print(f"quic_summary mode={'resumed' if resume else 'cold'} n={n} "
          f"send_unlock_p50_ms={_pct(unlock, 50):.3f} "
          f"send_unlock_p95_ms={_pct(unlock, 95):.3f} "
          f"handshake_p50_ms={_pct(hs, 50):.3f} "
          f"early_data_accepted={sum(1 for s in samples if s[2])}/{n}",
          flush=True)
    return 0 if results["fail"] == 0 and results["ok"] == parallel else 1


async def _start_servers(ports, cert, key, counters, host="0.0.0.0"):
    """Bind every port; returns the aioquic servers (close() each to stop)."""
    cfg = QuicConfiguration(is_client=False, alpn_protocols=ALPN)
    # max_early_data: aioquic has no configuration knob for it — a server-side
    # QuicConnection always builds its TLS context with
    # max_early_data=0xFFFFFFFF (the only value QUIC permits), so every ticket
    # issued here already allows 0-RTT.
    cfg.load_cert_chain(cert, key)
    tickets = {}  # in memory; .get, never .pop — one ticket serves many flows

    def _add(ticket):
        tickets[ticket.ticket] = ticket

    async def _drain(reader, writer):
        total = 0
        try:
            while True:
                chunk = await reader.read(65536)
                if not chunk:
                    break
                total += len(chunk)
            writer.write_eof()
        except Exception:
            pass
        counters["accepted"] += 1
        counters["bytes"] += total

    def _on_stream(reader, writer):
        asyncio.ensure_future(_drain(reader, writer))

    return [await serve(host, port, configuration=cfg,
                        session_ticket_fetcher=tickets.get,
                        session_ticket_handler=_add,
                        stream_handler=_on_stream)
            for port in ports]


async def run_server(ports, cert, key):
    counters = {"accepted": 0, "bytes": 0}
    servers = await _start_servers(ports, cert, key, counters)
    print(f"Listening on ports {ports}", flush=True)

    stop_event = asyncio.Event()

    def _handle_signal():
        print(f"Received {counters['bytes']} bytes across "
              f"{counters['accepted']} connections (final)", flush=True)
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, _handle_signal)
        except NotImplementedError:
            pass  # Windows dev/testing fallback — production target is Linux
    await stop_event.wait()
    for s in servers:
        s.close()


def _build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["client", "server"], required=True)
    ap.add_argument("--host", default=None, help="server host (client mode only)")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--port-count", type=int, default=1)
    ap.add_argument("--parallel", type=int, default=1000,
                    help="total measured connections (client mode); the "
                         "priming connection is extra")
    ap.add_argument("--bytes", type=int, default=1024,
                    help="payload bytes sent per connection (client mode)")
    ap.add_argument("--rate", type=float, default=0.0,
                    help="connection arrival rate in connections/sec (client "
                         "mode). 0 = all at once (burst)")
    ap.add_argument("--resume", action="store_true",
                    help="client mode: reuse the priming connection's session "
                         "ticket on every connection (0-RTT)")
    ap.add_argument("--cert", default=None, help="TLS certificate (server mode)")
    ap.add_argument("--key", default=None, help="TLS private key (server mode)")
    return ap


def main():
    args = _build_parser().parse_args()
    ports = list(range(args.port, args.port + max(args.port_count, 1)))

    if args.mode == "server":
        if not (args.cert and args.key):
            print("ERROR: --cert and --key are required for --mode server",
                  file=sys.stderr)
            return 2
        asyncio.run(run_server(ports, args.cert, args.key))
        return 0

    if not args.host:
        print("ERROR: --host is required for --mode client", file=sys.stderr)
        return 2
    return asyncio.run(run_client(args.host, ports, args.parallel, args.bytes,
                                  args.rate, args.resume))


if __name__ == "__main__":
    sys.exit(main())
