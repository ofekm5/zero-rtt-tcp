"""
Pins the QUIC arm of experiments/run.sh (STACK=baseline PROTO=quic) against the
mock transport from test_run_sh.py: the real run.sh runs end to end, every
remote call is recorded, and the assertions are on those calls and on the
report it writes.

No AWS, no SSH, no aioquic, no live infrastructure.
"""

import sys
from pathlib import Path

import pytest

from .test_run_sh import RECORDED, _calls, pytestmark, run_sh  # noqa: F401  (run_sh is a fixture)

_SUMMARY = {
    "cold": "quic_summary mode=cold n=1 send_unlock_p50_ms=101.250 "
            "send_unlock_p95_ms=103.500 handshake_p50_ms=101.250 early_data_accepted=0/1",
    "resumed": "quic_summary mode=resumed n=1 send_unlock_p50_ms=0.410 "
               "send_unlock_p95_ms=0.620 handshake_p50_ms=100.900 early_data_accepted=1/1",
}


def _quic(arm, client_reply=None):
    """Bash evaluated before run.sh: select the QUIC arm and teach the mock
    chain to answer the two QUIC-only commands. The client reply is one line
    because the mock transport wraps it in a JSON string."""
    reply = client_reply if client_reply is not None else f"Success: 1/1 {_SUMMARY[arm]}"
    return (
        f"PROTO=quic QUIC_RESUME={int(arm == 'resumed')}\n"
        "eval \"$(declare -f _reply | sed '1s/_reply/_healthy_reply/')\"\n"
        "_reply() { case \"$2\" in\n"
        f"    *loadgen_quic.py*'--mode client'*) echo '{reply}' ;;\n"
        "    *'ss -ulnp'*) echo LISTEN_OK ;;\n"
        "    *'ss -tlnp'*) echo LISTEN_NONE ;;\n"  # a QUIC server has no TCP listener
        "    *) _healthy_reply \"$@\" ;;\n"
        "esac; }"
    )


def _client_load(calls):
    return [c for c in calls if c.startswith("run client ") and "--mode client" in c]


def _report(run_sh, arm):
    reports = sorted((Path(run_sh).parent / "reports" / "baseline").glob(f"baseline-quic-{arm}-report-*.md"))
    assert reports, f"no QUIC {arm} report written"
    return reports[-1].read_text(encoding="utf-8")


@pytest.mark.parametrize("arm", ["cold", "resumed"])
def test_quic_arm_runs_the_quic_endpoints(run_sh, arm):
    rc, calls = _calls(run_sh, "baseline", "ssm", _quic(arm))
    assert rc == 0

    server = [c for c in calls if c.startswith("bg server ") and "nodes/server.sh" in c]
    assert len(server) == 1 and "PROTO=quic " in server[0]
    # The liveness check must look for a UDP socket: `ss -tlnp` never sees QUIC.
    assert [c for c in calls if c.startswith("stdout server ") and "ss -ulnp" in c]
    assert not [c for c in calls if "ss -tlnp" in c]

    (load,) = _client_load(calls)
    assert "nodes/loadgen_quic.py --mode client --host 10.1.2.10 --port 8080 --port-count 4" in load
    assert "nodes/loadgen.py" not in load
    # loadgen_quic.py rejects these two flags outright.
    assert "--think-ms" not in load and "--concurrency-limit" not in load
    assert ("--resume" in load) == (arm == "resumed")
    # The orchestrator bypasses nodes/client.sh, so it must ensure aioquic itself.
    assert "import aioquic" in load

    assert [c for c in calls if "pkill -f loadgen_quic.py" in c]


@pytest.mark.parametrize("arm", ["cold", "resumed"])
def test_quic_arm_skips_pcap_capture_and_analysis(run_sh, arm):
    _, calls = _calls(run_sh, "baseline", "ssm", _quic(arm))
    assert not [c for c in calls if "tcpdump" in c or "analyze_metrics.py" in c or ".pcap" in c]


def test_quic_arm_keeps_the_baseline_wan_and_endpoint_setup(run_sh):
    """Same netem leg and endpoint tuning as the TCP baseline — everything the
    TCP baseline does before starting its server, the QUIC arm does too."""
    _, quic = _calls(run_sh, "baseline", "ssm", _quic("cold"))
    _, tcp = RECORDED[("baseline", "ssm")]
    start = next(i for i, c in enumerate(tcp) if "nodes/server.sh" in c)
    want = [c.replace("pkill -f loadgen.py", "pkill -f loadgen_quic.py") for c in tcp[:start]]
    assert list(quic[:start]) == want


@pytest.mark.parametrize("arm", ["cold", "resumed"])
def test_quic_report_carries_the_summary_under_the_headline_tier(run_sh, arm):
    _calls(run_sh, "baseline", "ssm", _quic(arm))
    text = _report(run_sh, arm)

    latency = text.split("## Latency Summary", 1)[1].split("## ", 1)[0]
    lines = [ln.strip() for ln in latency.splitlines() if ln.strip() and ln.strip() != "```"]
    assert "Primary" in lines[0]
    assert lines[1] == _SUMMARY[arm]          # the client's line, verbatim, right under the headline
    assert "handshake_p50_ms=" in lines[1] and "early_data_accepted=" in lines[1]
    assert "no samples found" not in latency  # the pcap metric rows are not printed for QUIC

    assert f"| `QUIC_RESUME` | {int(arm == 'resumed')} ({arm}) |" in text
    assert "## Endpoint Packet Analysis" not in text


def test_quic_report_states_the_comparison_caveats(run_sh):
    _calls(run_sh, "baseline", "ssm", _quic("resumed"))
    notes = _report(run_sh, "resumed").split("## Notes", 1)[1]
    assert "plaintext" in notes and "QUIC always encrypts" in notes
    assert "reuses its session ticket" in notes
    assert "A2" in notes and "early_data_accepted" in notes and "handshake_p50_ms" in notes


def test_cold_and_resumed_are_separate_reports(run_sh):
    for arm in ("cold", "resumed"):
        _calls(run_sh, "baseline", "ssm", _quic(arm))
    assert "mode=cold" in _report(run_sh, "cold") and "mode=resumed" not in _report(run_sh, "cold")
    assert "mode=resumed" in _report(run_sh, "resumed")


def test_missing_quic_summary_fails_the_run(run_sh):
    """A client that finished without printing quic_summary leaves nothing to
    report — that is a failed run, not a green one with an empty headline."""
    rc, _ = _calls(run_sh, "baseline", "ssm", _quic("cold", client_reply="Success: 1/1"))
    assert rc == 1


def test_quic_server_not_listening_on_udp_fails_the_run(run_sh):
    override = _quic("cold").replace("*'ss -ulnp'*) echo LISTEN_OK", "*'ss -ulnp'*) echo LISTEN_NONE")
    rc, _ = _calls(run_sh, "baseline", "ssm", override)
    assert rc == 1


@pytest.mark.parametrize("stack,transport,override", [
    ("0rtt", "ssm", "PROTO=quic"),                   # the DPDK data plane is TCP-only
    ("0rtt", "ssh", "PROTO=quic"),
    ("baseline", "ssm", "PROTO=udp"),                # unknown PROTO
    ("baseline", "ssm", "PROTO=quic QUIC_RESUME=yes"),
])
def test_rejected_proto_exits_2_before_any_remote_call(run_sh, stack, transport, override):
    assert _calls(run_sh, stack, transport, override) == (2, ())


@pytest.mark.parametrize("override", ["PROTO=tcp", "PROTO=tcp QUIC_RESUME=1", "unset PROTO QUIC_RESUME"])
def test_tcp_baseline_is_unchanged_by_the_proto_switch(run_sh, override):
    rc, calls = _calls(run_sh, "baseline", "ssm", override)
    want_rc, want = RECORDED[("baseline", "ssm")]
    assert (rc, calls) == (want_rc, want)


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
