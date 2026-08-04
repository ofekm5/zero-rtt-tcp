"""
Tests for experiments/utils/endpoint.sh — the shared endpoint setup/capture/
analysis module used by BOTH the 0-RTT stack (run_core.sh) and the plain-TCP
baseline (baseline-tcp/run_experiment.sh).

The functions here drive real VMs over SSM, so the tests substitute mock
remote_run/remote_bg/remote_stdout shims and assert on the commands the module
*would* issue. That is enough to pin the two things most likely to regress
silently and invalidate a measurement:

  1. netem placement — the full emulated RTT on the SERVER egress only. Split
     across both endpoints (the previous behavior) it halves the measurable
     0-RTT saving, and nothing in the run output would say so.
  2. metric ordering — send_unlock leads, because it is the only metric that
     isolates what the spoof buys.

No AWS, no DPDK, no live infrastructure.
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

_TESTS_DIR = Path(__file__).parent
_ENDPOINT_SH = _TESTS_DIR.parent / "endpoint.sh"
_HARNESS_SH = _TESTS_DIR / "endpoint_mock_harness.sh"

pytestmark = pytest.mark.skipif(
    shutil.which("bash") is None, reason="bash not available on this host"
)


def _run(func_args, netem_rtt_ms="100"):
    """Source endpoint.sh under the mock harness and call one of its functions.

    Returns (stdout, trace_lines).

    Two portability constraints shape this call:
      - Paths are RELATIVE to cwd=_TESTS_DIR, because the bash on PATH may be a
        POSIX build that cannot open a Windows-style `C:/...` path at all.
      - NETEM_RTT_MS is an ARGUMENT, not an env var, because some bash builds
        sanitize the inherited environment — an env-configured harness would
        silently run the default and the test would assert nothing.
    """
    result = subprocess.run(
        ["bash", _HARNESS_SH.name, netem_rtt_ms, f"../{_ENDPOINT_SH.name}",
         *func_args],
        capture_output=True, text=True, cwd=str(_TESTS_DIR),
    )
    assert result.returncode == 0, (
        f"harness exited {result.returncode}\nstdout: {result.stdout}\n"
        f"stderr: {result.stderr}"
    )
    trace = [l[len("TRACE|"):] for l in result.stderr.splitlines()
             if l.startswith("TRACE|")]
    return result.stdout, trace


def _cmds_for(trace, node):
    return [l.split("|", 1)[1] for l in trace if l.split("|", 1)[0] == node]


class TestNetemPlacement:
    """The full emulated RTT belongs on the Server egress, and nowhere else.

    A root netem qdisc delays EGRESS only. With 50ms on each endpoint, baseline
    connect() costs a full 100ms RTT but 0-RTT connect() costs 50ms — the SYN
    still pays the client's egress before the spoofed SYN-ACK returns. The
    measured saving was therefore half the emulated RTT.
    """

    def test_server_gets_the_full_rtt(self):
        _, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        server = " ".join(_cmds_for(trace, "SERVER"))
        assert "netem delay 100ms" in server

    def test_client_egress_is_left_clean(self):
        _, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        client = " ".join(_cmds_for(trace, "CLIENT"))
        assert "qdisc del dev eth0 root" in client, "stale qdiscs must be cleared"
        assert "netem delay" not in client, (
            "client egress must carry no netem — delay there sits on a LAN hop "
            "0-RTT cannot remove, and halves the measurable saving"
        )

    def test_rtt_is_configurable(self):
        _, trace = _run(["endpoint_tune", "CLIENT", "SERVER"],
                        netem_rtt_ms="250")
        assert "netem delay 250ms" in " ".join(_cmds_for(trace, "SERVER"))

    def test_placement_is_verified_not_assumed(self):
        """A silently-failed tc turns the run into an intra-VPC measurement."""
        out, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "SERVER"))
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "CLIENT"))
        assert "[PASS]" in out and "[FAIL]" not in out


class TestSharedEndpointSetup:
    """Both stacks must get identical endpoint conditions, or the comparison
    between them is confounded."""

    def test_both_endpoints_are_tuned(self):
        _, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        for node in ("CLIENT", "SERVER"):
            joined = " ".join(_cmds_for(trace, node))
            assert "tcp_timestamps=0" in joined
            assert "tcp_window_scaling=0" in joined
            assert "tcp_sack=0" in joined
            assert "mtu 1500" in joined
            assert "gro off" in joined

    def test_capture_starts_on_both_endpoints(self):
        _, trace = _run(
            ["endpoint_capture_start", "CLIENT", "SERVER", "portrange 8080-8083"])
        client = " ".join(_cmds_for(trace, "CLIENT"))
        server = " ".join(_cmds_for(trace, "SERVER"))
        assert "client_side.pcap" in client and "portrange 8080-8083" in client
        assert "server_side.pcap" in server and "portrange 8080-8083" in server

    def test_capture_stops_on_both_endpoints(self):
        _, trace = _run(["endpoint_capture_stop", "CLIENT", "SERVER"])
        assert "pkill tcpdump" in " ".join(_cmds_for(trace, "CLIENT"))
        assert "pkill tcpdump" in " ".join(_cmds_for(trace, "SERVER"))


class TestLatencySummaryOrdering:
    """send_unlock is the primary result; FCT and server_gap are throughput-bound
    and must not be presented as peers of it."""

    def test_send_unlock_leads(self):
        out, _ = _run(["endpoint_latency_summary", "some=metrics"])
        assert out.index("send_unlock") < out.index("metric=fct")
        assert out.index("send_unlock") < out.index("server_gap")

    def test_secondary_metrics_are_labelled_as_such(self):
        out, _ = _run(["endpoint_latency_summary", "some=metrics"])
        assert "Primary" in out
        assert "Secondary" in out
        assert "not evidence about the handshake" in out


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
