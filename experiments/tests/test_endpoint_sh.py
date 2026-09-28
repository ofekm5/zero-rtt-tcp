"""
Tests for experiments/lib/endpoint.sh — the shared endpoint setup/capture/
analysis module used by BOTH the 0-RTT stack (core.sh) and the plain-TCP
baseline (baseline-tcp/run_experiment.sh).

The functions here drive real VMs over SSM, so the tests substitute mock
remote_run/remote_bg/remote_stdout shims and assert on the commands the module
*would* issue. That is enough to pin the two things most likely to regress
silently and invalidate a measurement:

  1. netem placement — the emulated WAN on the ClientNIC<->ServerNIC leg, half
     per direction, with both endpoints clean. Any endpoint placement makes an
     FCT gain structurally impossible (roadmap.md F2), and nothing in the run
     output would say so.
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
_ENDPOINT_SH = _TESTS_DIR.parent / "lib" / "endpoint.sh"
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
        ["bash", _HARNESS_SH.name, netem_rtt_ms, f"../lib/{_ENDPOINT_SH.name}",
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
    """The emulated WAN belongs on the ClientNIC<->ServerNIC leg, and nowhere else.

    A root netem qdisc delays EGRESS only, so placement decides which metric can
    move. Both earlier placements were wrong in different ways:
      - 50ms on each endpoint: the SYN paid the Client's own egress before the
        spoof could return, halving the measured `send_unlock` saving.
      - full RTT on Server egress: `send_unlock` correct, but an FCT gain became
        structurally impossible — the real SYN-ACK is the packet ServerNIC waits
        on before flushing buffered client data, so it arrived exactly one RTT
        late by construction (2026-08-04 measured FCT at -0.09 ms).
    Only the middle leg lets the ServerNIC's hold overlap WAN transit.
    """

    def test_both_endpoints_are_left_clean(self):
        _, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        for node in ("CLIENT", "SERVER"):
            cmds = " ".join(_cmds_for(trace, node))
            assert "qdisc del dev eth0 root" in cmds, "stale qdiscs must be cleared"
            assert "netem delay" not in cmds, (
                f"{node} egress must carry no netem — an endpoint qdisc cannot "
                "model the middle leg and silently reintroduces the F2 confound"
            )

    def test_middle_leg_gets_half_the_rtt_on_each_side(self):
        _, trace = _run(["wan_tune_middle_leg",
                         "CLIENTNIC", "eth1", "SERVERNIC", "eth0"])
        assert "netem delay 50ms" in " ".join(_cmds_for(trace, "CLIENTNIC"))
        assert "netem delay 50ms" in " ".join(_cmds_for(trace, "SERVERNIC"))

    def test_middle_leg_uses_the_named_interfaces(self):
        """ClientNIC reaches the Middle subnet over eth1, ServerNIC over eth0.
        Applying the delay to the wrong interface silently delays the wrong leg."""
        _, trace = _run(["wan_tune_middle_leg",
                         "CLIENTNIC", "eth1", "SERVERNIC", "eth0"])
        assert "dev eth1 root netem" in " ".join(_cmds_for(trace, "CLIENTNIC"))
        assert "dev eth0 root netem" in " ".join(_cmds_for(trace, "SERVERNIC"))

    def test_rtt_is_configurable_and_split_evenly(self):
        _, trace = _run(["wan_tune_middle_leg",
                         "CLIENTNIC", "eth1", "SERVERNIC", "eth0"],
                        netem_rtt_ms="250")
        for node in ("CLIENTNIC", "SERVERNIC"):
            assert "netem delay 125ms" in " ".join(_cmds_for(trace, node))

    def test_dpdk_half_rtt_matches_the_baseline_netem(self):
        """Both stacks must model the same total RTT or the comparison is void.
        wan_delay_us() feeds --wan-delay-us; netem gets NETEM_RTT_MS/2 per side."""
        out, _ = _run(["wan_delay_us"])
        assert out.strip() == "50000", "100ms RTT => 50ms => 50000us per direction"
        out, _ = _run(["wan_delay_us"], netem_rtt_ms="250")
        assert out.strip() == "125000"

    def test_endpoint_placement_is_verified_not_assumed(self):
        """A leftover endpoint qdisc must fail the run, not be assumed absent."""
        out, trace = _run(["endpoint_tune", "CLIENT", "SERVER"])
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "SERVER"))
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "CLIENT"))
        assert "[PASS]" in out and "[FAIL]" not in out

    def test_middle_leg_placement_is_verified_not_assumed(self):
        """A silently-failed tc turns the run into an intra-VPC measurement
        where one RTT is ~1.5ms and no 0-RTT benefit is observable at all."""
        out, trace = _run(["wan_tune_middle_leg",
                           "CLIENTNIC", "eth1", "SERVERNIC", "eth0"])
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "CLIENTNIC"))
        assert any("tc qdisc show" in c for c in _cmds_for(trace, "SERVERNIC"))
        assert "[PASS]" in out and "[FAIL]" not in out

    def test_middle_leg_installs_tc_first(self):
        """iproute-tc is not in the base AMI (F15); without it every netem
        command fails silently and the run measures the intra-VPC RTT."""
        _, trace = _run(["wan_tune_middle_leg",
                         "CLIENTNIC", "eth1", "SERVERNIC", "eth0"])
        for node in ("CLIENTNIC", "SERVERNIC"):
            assert "iproute-tc" in " ".join(_cmds_for(trace, node))


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
