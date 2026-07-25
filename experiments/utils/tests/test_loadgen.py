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


async def _run_roundtrip(port, port_count, parallel, nbytes):
    ports = loadgen._parse_ports(port, port_count)
    counters = {"accepted": 0, "bytes": 0}
    # _start_servers() binds and begins accepting immediately — no need to run
    # (or cancel) serve_forever() in a test. See loadgen._start_servers docstring.
    servers = await loadgen._start_servers(ports, counters)
    try:
        rc = await loadgen.run_client("127.0.0.1", ports, parallel, nbytes, parallel)
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


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
