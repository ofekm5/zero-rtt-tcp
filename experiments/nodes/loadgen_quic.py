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
    python3 loadgen_quic.py --mode rate-spike   # loopback; prints sustained_rate=<n>
"""

import argparse
import asyncio
import contextlib
import io
import math
import signal
import ssl
import subprocess
import sys
import tempfile
import time

from aioquic.asyncio import connect, serve
from aioquic.quic.configuration import QuicConfiguration

ALPN = ["loadgen"]
TICKET_WAIT_S = 5.0
# rate-spike mode: cold-handshake rates tried in order, seconds held at each,
# and the sleep whose overshoot is the event-loop lag.
SPIKE_RATES = (50, 100, 200, 400, 800, 1600, 3200)
SPIKE_STEP_S = 2.0
LAG_TICK_S = 0.01


def _pct(values, p):
    """Nearest-rank percentile; 0.0 for an empty sample."""
    if not values:
        return 0.0
    s = sorted(values)
    return s[min(len(s) - 1, max(0, math.ceil(p / 100.0 * len(s)) - 1))]


def _client_config(ticket=None):
    # CERT_NONE: the server runs a throwaway self-signed cert on an isolated
    # lab network; this tool measures handshake timing, not authenticity.
    cfg = QuicConfiguration(is_client=True, alpn_protocols=ALPN,
                            verify_mode=ssl.CERT_NONE)
    cfg.session_ticket = ticket
    return cfg


async def _exchange(proto, nbytes):
    """Send nbytes on one stream and half-close; returns the reader — the
    caller awaits reader.read() for the server's close."""
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


async def _client_conn(host, port, nbytes, ticket, samples, results, sem):
    resume = ticket is not None
    async with sem:
        try:
            t0 = time.monotonic()
            # Resuming: connect() returns before the handshake, so the write
            # below goes out as 0-RTT early data in the first flight. Cold:
            # connect() returns once the handshake is complete — the first
            # moment a write is permitted.
            async with connect(host, port, configuration=_client_config(ticket),
                               wait_connected=not resume) as proto:
                unlock = time.monotonic()
                reader = await _exchange(proto, nbytes)
                await proto.wait_connected()  # no-op when cold
                hs = unlock if not resume else time.monotonic()
                # aioquic-internal: verified against the aioquic==1.3.0 pinned
                # in nodes/client.sh, nodes/server.sh and lib/measure.sh.
                early = bool(proto._quic.tls.early_data_accepted)
                # A terminated connection also ends the stream with b"", so
                # only the server's ack byte proves the payload was received.
                if not await reader.read():
                    raise ConnectionError("stream ended without the server's ack")
        except Exception as e:
            results["fail"] += 1
            results.setdefault("error", repr(e))
            return
    results["ok"] += 1
    samples.append(((unlock - t0) * 1000.0, (hs - t0) * 1000.0, early))


async def run_client(host, ports, parallel, nbytes, rate=0.0, resume=False,
                     concurrency_limit=None):
    """Open `parallel` QUIC connections paced at `rate` conn/s (0 = burst),
    on the same absolute timeline as loadgen.run_client, with at most
    `concurrency_limit` in flight (None = parallel)."""
    ticket = await _prime(host, ports[0], nbytes)
    if resume and ticket is None:
        print("ERROR: priming connection got no session ticket; cannot resume",
              file=sys.stderr)
        return 1

    sem = asyncio.Semaphore(concurrency_limit or parallel)
    results = {"ok": 0, "fail": 0}
    samples = []
    tasks = []
    t0 = time.monotonic()
    for i in range(parallel):
        if rate > 0:
            delay = (t0 + i / rate) - time.monotonic()
            # Behind schedule: still yield, so running connections progress
            # instead of the rest of the run being spawned in one burst.
            await asyncio.sleep(max(delay, 0))
        tasks.append(asyncio.ensure_future(
            _client_conn(host, ports[i % len(ports)], nbytes,
                         ticket if resume else None, samples, results, sem)))
    spawn_dt = time.monotonic() - t0
    await asyncio.gather(*tasks)
    dt = time.monotonic() - t0

    achieved = (parallel / spawn_dt) if spawn_dt > 0 else float("inf")
    print(f"Arrival: rate={rate:g} conn/s requested, {achieved:.0f} conn/s "
          f"achieved over {spawn_dt:.3f}s")
    print(f"Transfer complete: {results['ok']}/{parallel} connections ok, "
          f"{results['fail']} failed, duration={dt:.3f}s")
    print(f"Success: {results['ok']}/{parallel}")
    if "error" in results:
        print(f"First connection error: {results['error']}", file=sys.stderr)
    unlock = [s[0] for s in samples]
    hs = [s[1] for s in samples]
    n = len(samples)
    # Parsed format: lib/core.sh (pass/fail gate), lib/endpoint.sh
    # (quic_latency_summary) and tests/test_loadgen_quic.py match this line.
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
            writer.write(b"\x01")  # ack: the client counts a flow ok only on it
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


def _write_cert(directory):
    """Throwaway self-signed cert for the rate-spike loopback server."""
    import datetime
    from pathlib import Path

    from cryptography import x509  # aioquic dependency
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import NameOID

    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "localhost")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(name).issuer_name(name)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=1))
            .sign(key, hashes.SHA256()))
    crt, pem = Path(directory) / "quic.crt", Path(directory) / "quic.key"
    crt.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    pem.write_bytes(key.private_bytes(serialization.Encoding.PEM,
                                      serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()))
    return str(crt), str(pem)


async def _lag_probe(lags):
    """Record how late each LAG_TICK_S sleep wakes up, in ms."""
    while True:
        t = time.monotonic()
        await asyncio.sleep(LAG_TICK_S)
        lags.append((time.monotonic() - t - LAG_TICK_S) * 1000.0)


async def run_rate_spike(port, nbytes, max_lag_ms):
    """Ramp the cold-handshake arrival rate against a loopback server and
    report the highest rate whose event-loop lag p95 stays under max_lag_ms
    with no failed connection. Stops at the first rate that breaches."""
    sustained = 0
    for rate in SPIKE_RATES:
        lags = []
        probe = asyncio.ensure_future(_lag_probe(lags))
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                rc = await run_client("127.0.0.1", [port],
                                      int(rate * SPIKE_STEP_S), nbytes,
                                      rate=float(rate))
        finally:
            probe.cancel()
        lag = _pct(lags, 95)
        ok = rc == 0 and lag <= max_lag_ms
        print(f"rate_spike rate={rate} lag_p95_ms={lag:.3f} "
              f"failed={int(rc != 0)} ok={int(ok)}", flush=True)
        if not ok:
            break
        sustained = rate
    print(f"sustained_rate={sustained}", flush=True)
    return 0


def _rate_spike_main(port, nbytes, max_lag_ms):
    # The server runs as its own process so the lag measured is the client's
    # alone, as it will be on the client VM.
    with tempfile.TemporaryDirectory() as d:
        cert, key = _write_cert(d)
        srv = subprocess.Popen(
            [sys.executable, __file__, "--mode", "server", "--port", str(port),
             "--cert", cert, "--key", key],
            stdout=subprocess.PIPE, text=True)
        try:
            if "Listening" not in srv.stdout.readline():
                print("ERROR: loopback QUIC server did not start",
                      file=sys.stderr)
                return 1
            return asyncio.run(run_rate_spike(port, nbytes, max_lag_ms))
        finally:
            srv.terminate()
            srv.wait()


def _build_parser():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mode", choices=["client", "server", "rate-spike"],
                    required=True)
    ap.add_argument("--max-lag-ms", type=float, default=20.0,
                    help="rate-spike mode: event-loop lag p95 above this "
                         "means the rate is not sustained")
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
    ap.add_argument("--concurrency-limit", type=int, default=None,
                    help="client mode: max connections in flight "
                         "(default = --parallel)")
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

    if args.mode == "rate-spike":
        return _rate_spike_main(args.port, args.bytes, args.max_lag_ms)

    if not args.host:
        print("ERROR: --host is required for --mode client", file=sys.stderr)
        return 2
    return asyncio.run(run_client(args.host, ports, args.parallel, args.bytes,
                                  args.rate, args.resume,
                                  args.concurrency_limit))


if __name__ == "__main__":
    sys.exit(main())
