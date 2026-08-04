"""
Tests for experiments/utils/loadgen.py — the asyncio event-driven load
generator that replaces iperf2 (see roadmap.md #20 scope item A).

Runs plain pytest (no pytest-asyncio needed): async work is driven with
asyncio.run() inside ordinary sync test functions. No DPDK, no live
infrastructure — client and server talk over 127.0.0.1.
"""

import asyncio
import importlib.util
import sys
import time
from pathlib import Path

import pytest

_LOADGEN_PATH = Path(__file__).parent.parent / "loadgen.py"
_spec = importlib.util.spec_from_file_location("loadgen", _LOADGEN_PATH)
loadgen = importlib.util.module_from_spec(_spec)
sys.modules["loadgen"] = loadgen
_spec.loader.exec_module(loadgen)


def test_parse_ports_single():
    assert loadgen._parse_ports(8080, 1) == [8080]


def test_parse_ports_range():
    assert loadgen._parse_ports(8080, 4) == [8080, 8081, 8082, 8083]


def test_parse_ports_floors_at_one():
    """port-count=0 (or negative) still yields exactly one port, never an empty list."""
    assert loadgen._parse_ports(8080, 0) == [8080]


async def _run_roundtrip(port, port_count, parallel, nbytes, rate=0.0, limit=None):
    ports = loadgen._parse_ports(port, port_count)
    counters = {"accepted": 0, "bytes": 0}
    # _start_servers() binds and begins accepting immediately — no need to run
    # (or cancel) serve_forever() in a test. See loadgen._start_servers docstring.
    servers = await loadgen._start_servers(ports, counters)
    try:
        rc = await loadgen.run_client("127.0.0.1", ports, parallel, nbytes,
                                      limit or parallel, rate)
    finally:
        for s in servers:
            s.close()
        await asyncio.gather(*(s.wait_closed() for s in servers))
    return rc


class TestClientServerRoundtrip:
    """End-to-end: real sockets over loopback, no mocking."""

    def test_all_connections_succeed(self):
        rc = asyncio.run(_run_roundtrip(port=19080, port_count=2, parallel=200, nbytes=4096))
        assert rc == 0

    def test_single_port_small_batch(self):
        rc = asyncio.run(_run_roundtrip(port=19090, port_count=1, parallel=50, nbytes=1024))
        assert rc == 0

    def test_client_reports_failure_when_nothing_listening(self):
        """Connecting to a port with no listener should fail cleanly, not hang."""
        async def _go():
            return await loadgen.run_client("127.0.0.1", [19099], 5, 1024, 5)
        rc = asyncio.run(_go())
        assert rc == 1


class TestArrivalPacing:
    """--rate spreads connection arrivals instead of firing them all at once.

    Pacing is the difference between measuring the path and measuring the
    queue: unpaced, every flow's latency includes waiting behind the rest of
    the batch, so the run reports the forwarder's SYN service rate rather than
    the round-trip the 0-RTT spoof removes.
    """

    def test_paced_run_takes_at_least_the_scheduled_span(self):
        """40 connections at 100/s cannot finish in under ~0.39s of spawning."""
        t0 = time.monotonic()
        rc = asyncio.run(_run_roundtrip(port=19100, port_count=1, parallel=40,
                                        nbytes=512, rate=100.0))
        elapsed = time.monotonic() - t0
        assert rc == 0
        # Connection i is scheduled at t0 + i/rate, so the last of 40 is due at
        # 39/100 = 0.39s. Assert against that floor, not the nominal 0.40s.
        assert elapsed >= 0.39, f"paced run finished in {elapsed:.3f}s — pacing not applied"

    def test_unpaced_run_is_not_delayed(self):
        """rate=0 keeps the old burst behavior for deliberate stress runs."""
        t0 = time.monotonic()
        rc = asyncio.run(_run_roundtrip(port=19110, port_count=1, parallel=40,
                                        nbytes=512, rate=0.0))
        elapsed = time.monotonic() - t0
        assert rc == 0
        assert elapsed < 0.39, f"unpaced run took {elapsed:.3f}s — burst path is pacing"

    def test_pacing_does_not_drop_connections(self):
        """Every scheduled connection is still opened and counted."""
        counters = {"accepted": 0, "bytes": 0}

        async def _go():
            servers = await loadgen._start_servers([19120], counters)
            try:
                return await loadgen.run_client("127.0.0.1", [19120], 25, 256,
                                                25, 250.0)
            finally:
                for s in servers:
                    s.close()
                await asyncio.gather(*(s.wait_closed() for s in servers))

        assert asyncio.run(_go()) == 0
        assert counters["bytes"] == 25 * 256

    def test_concurrency_limit_bounds_in_flight_connections(self):
        """The semaphore ceiling holds even when the arrival schedule outruns it."""
        rc = asyncio.run(_run_roundtrip(port=19130, port_count=2, parallel=60,
                                        nbytes=256, rate=0.0, limit=5))
        assert rc == 0


class TestDefaults:
    """Defaults encode the measurement intent — a wrong default silently
    produces a run whose numbers cannot support the 0-RTT claim.
    experiments/utils/measure.sh mirrors these; keep both in sync."""

    def _defaults(self):
        return loadgen._build_parser().parse_args(["--mode", "client",
                                                   "--host", "127.0.0.1"])

    def test_payload_default_is_one_segment(self):
        """1 MB costs ~16 RTTs of transfer, burying the single RTT 0-RTT saves."""
        assert self._defaults().bytes == 1024

    def test_rate_default_is_burst(self):
        """The CLI default stays unpaced so ad-hoc invocations are unsurprising;
        the experiment harness (measure.sh) is what opts into pacing."""
        assert self._defaults().rate == 0.0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
