"""
Loopback test for experiments/nodes/loadgen_quic.py — pins the cold-vs-resumed
contract the four-arm comparison rests on: a resumed connection unlocks its
first write before a cold one, and the server really accepted the 0-RTT data.

Plain pytest, real aioquic client and server over 127.0.0.1; no netem, no VMs.
"""

import asyncio
import contextlib
import importlib.util
import io
import re
import sys
from pathlib import Path

import pytest

pytest.importorskip("aioquic", reason="aioquic is not installed — "
                    "pip install aioquic to run the QUIC loopback test")

_PATH = Path(__file__).parent.parent / "nodes" / "loadgen_quic.py"
_spec = importlib.util.spec_from_file_location("loadgen_quic", _PATH)
loadgen_quic = importlib.util.module_from_spec(_spec)
sys.modules["loadgen_quic"] = loadgen_quic
_spec.loader.exec_module(loadgen_quic)

N = 10
PORT = 19200

_SUMMARY_RE = re.compile(
    r"^quic_summary mode=(?P<mode>cold|resumed) n=(?P<n>\d+) "
    r"send_unlock_p50_ms=(?P<unlock_p50>\d+\.\d+) "
    r"send_unlock_p95_ms=(?P<unlock_p95>\d+\.\d+) "
    r"handshake_p50_ms=(?P<hs_p50>\d+\.\d+) "
    r"early_data_accepted=(?P<early>\d+)/(?P<early_n>\d+)$",
    re.MULTILINE)


def _summary(out):
    matches = list(_SUMMARY_RE.finditer(out))
    assert len(matches) == 1, f"expected one quic_summary line, got:\n{out}"
    d = matches[0].groupdict()
    return {k: (v if k == "mode" else float(v) if "." in v else int(v))
            for k, v in d.items()}


@pytest.fixture(scope="module")
def arms(tmp_path_factory):
    """Run a cold and a resumed client against one loopback server."""
    cert, key = loadgen_quic._write_cert(tmp_path_factory.mktemp("quic"))
    outs = {}

    async def _go():
        counters = {"accepted": 0, "bytes": 0}
        servers = await loadgen_quic._start_servers([PORT], cert, key, counters,
                                                    host="127.0.0.1")
        try:
            for resume in (False, True):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    rc = await loadgen_quic.run_client(
                        "127.0.0.1", [PORT], N, 1024, rate=50.0, resume=resume)
                outs["resumed" if resume else "cold"] = (rc, buf.getvalue())
        finally:
            for s in servers:
                s.close()

    asyncio.run(_go())
    return outs


def test_both_arms_complete(arms):
    assert arms["cold"][0] == 0, arms["cold"][1]
    assert arms["resumed"][0] == 0, arms["resumed"][1]


def test_quic_summary_line_parses(arms):
    for mode in ("cold", "resumed"):
        s = _summary(arms[mode][1])
        assert s["mode"] == mode
        assert s["n"] == N
        assert s["early_n"] == N
        assert s["unlock_p95"] >= s["unlock_p50"] >= 0.0


def test_early_data_accepted_on_every_resumed_flow_and_no_cold_flow(arms):
    """Fewer than n resumed means resumption silently fell back to 1-RTT."""
    assert _summary(arms["resumed"][1])["early"] == N
    assert _summary(arms["cold"][1])["early"] == 0


def test_resumed_send_unlock_is_below_cold(arms):
    cold = _summary(arms["cold"][1])
    resumed = _summary(arms["resumed"][1])
    assert resumed["unlock_p50"] < cold["unlock_p50"], (cold, resumed)
    # A resumed flow still does a handshake; only the first write is unlocked
    # ahead of it.
    assert resumed["unlock_p50"] < resumed["hs_p50"], resumed


@pytest.mark.parametrize("n,p,idx", [(1, 50, 0), (2, 50, 0), (10, 50, 4),
                                     (20, 50, 9), (20, 95, 18), (100, 95, 94),
                                     (3, 100, 2)])
def test_pct_is_nearest_rank(n, p, idx):
    # Shuffled-ish input: _pct must sort, and values equal their own rank index.
    assert loadgen_quic._pct(list(range(n))[::-1], p) == idx


def test_pct_of_empty_sample_is_zero():
    assert loadgen_quic._pct([], 50) == 0.0
