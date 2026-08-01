"""
Unit tests for experiments/utils/analyze_metrics.py

The analyzer parses `tcpdump -r <pcap> -nn -tt` text output. These tests feed
synthetic tcpdump-format text directly via the --client-text / --server-text
inputs, so they run anywhere (no scapy, no tcpdump binary required). The real
`tcpdump -r` invocation on the capture hosts is exercised by the live
integration experiment, not here.

No DPDK or live infrastructure required.
"""

import csv
import os
import subprocess
import sys
from pathlib import Path
from typing import List

import pytest

# Locate the analyzer script relative to this test file:
# tests/ -> utils/ -> analyze_metrics.py
_UTILS_DIR = Path(__file__).parent.parent
_ANALYZER = str(_UTILS_DIR / "analyze_metrics.py")

# Allow importing the analyzer module directly for unit-level tests.
sys.path.insert(0, str(_UTILS_DIR))
import analyze_metrics  # noqa: E402

_ENV = os.environ.copy()


# --------------------------------------------------------------------------- #
# tcpdump-text builders
# --------------------------------------------------------------------------- #

CLIENT_IP = "10.0.0.1"
CLIENT_PORT = 54321
SERVER_IP = "10.0.0.2"
SERVER_PORT = 5001


def _td(ts: float, sip: str, sport: int, dip: str, dport: int,
        flags: str, length: int = 0) -> str:
    """One `tcpdump -nn -tt` line. flags is the tcpdump flag string: S, S., P., F., '.'"""
    return (f"{ts:.6f} IP {sip}.{sport} > {dip}.{dport}: "
            f"Flags [{flags}], seq 1, ack 1, win 100, length {length}")


def _write_text(lines: List[str], path: str) -> None:
    Path(path).write_text("\n".join(lines) + "\n")


def _build_client_text(
    t0: float = 0.0,
    syn_to_payload_ms: float = 100.0,
    payload_to_fin_ms: float = 50.0,
    include_syn: bool = True,
    include_payload: bool = True,
    include_fin: bool = True,
) -> List[str]:
    """
    Build client-side tcpdump text:
      t0+0ms                : SYN     (client → server)
      t0+5ms                : SYN-ACK (server → client)
      t0+syn_to_payload_ms  : DATA    (client → server, payload>0)
      t0+..+payload_to_fin  : FIN     (client → server)
    """
    lines = []
    if include_syn:
        lines.append(_td(t0, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "S", 0))
        lines.append(_td(t0 + 0.005, SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT, "S.", 0))
    if include_payload:
        t_payload = t0 + syn_to_payload_ms / 1000.0
        lines.append(_td(t_payload, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "P.", 11))
    if include_fin:
        t_fin = t0 + (syn_to_payload_ms + payload_to_fin_ms) / 1000.0
        lines.append(_td(t_fin, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "F.", 0))
    return lines


def _build_server_text(
    t0: float = 0.0,
    syn_ack_delay_ms: float = 5.0,
    payload_delay_ms: float = 100.0,
    include_syn_ack: bool = True,
    include_inbound_payload: bool = True,
) -> List[str]:
    """
    Build server-side tcpdump text:
      t0+0ms            : SYN     (client → server, arrives at server host)
      t0+syn_ack_delay  : SYN-ACK (server → client)
      t0+payload_delay  : DATA    (client → server, payload>0)
    """
    lines = [_td(t0, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "S", 0)]
    if include_syn_ack:
        t_sa = t0 + syn_ack_delay_ms / 1000.0
        lines.append(_td(t_sa, SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT, "S.", 0))
    if include_inbound_payload:
        t_data = t0 + payload_delay_ms / 1000.0
        lines.append(_td(t_data, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "P.", 11))
    return lines


# --------------------------------------------------------------------------- #
# Helpers for running the analyzer
# --------------------------------------------------------------------------- #

def _run_analyzer(args: List[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, _ANALYZER] + args,
        capture_output=True, text=True, env=_ENV,
    )


def _parse_metric_lines(stdout: str) -> dict:
    metrics = {}
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("metric="):
            continue
        parts = {}
        for token in line.split():
            if "=" in token:
                k, v = token.split("=", 1)
                parts[k] = v
        if "metric" in parts:
            metrics[parts["metric"]] = parts
    return metrics


def _parse_missing_lines(stdout: str) -> List[str]:
    missing = []
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("missing="):
            token = line.split()[0]
            _, event = token.split("=", 1)
            missing.append(event)
    return missing


# --------------------------------------------------------------------------- #
# parse_line unit tests
# --------------------------------------------------------------------------- #

class TestParseLine:
    def test_parse_syn(self):
        p = analyze_metrics.parse_line(
            "1000.000000 IP 10.0.0.1.54321 > 10.0.0.2.5001: Flags [S], seq 1, win 100, length 0")
        assert p is not None
        assert p.src == "10.0.0.1" and p.sport == 54321
        assert p.dst == "10.0.0.2" and p.dport == 5001
        assert p.flags == "S" and p.length == 0
        assert p.time == 1000.0

    def test_parse_data_with_payload(self):
        p = analyze_metrics.parse_line(
            "1000.100000 IP 10.0.0.1.54321 > 10.0.0.2.5001: Flags [P.], seq 1:1461, ack 1, win 211, length 1460")
        assert p is not None and p.length == 1460 and p.flags == "P."

    def test_parse_non_ip_line_returns_none(self):
        assert analyze_metrics.parse_line("12:00:00.000 ARP, Request who-has ...") is None
        assert analyze_metrics.parse_line("") is None
        assert analyze_metrics.parse_line("garbage line") is None

    def test_flag_classifiers(self):
        assert analyze_metrics._is_syn("S")
        assert not analyze_metrics._is_syn("S.")
        assert analyze_metrics._is_syn_ack("S.")
        assert not analyze_metrics._is_syn_ack("S")
        assert analyze_metrics._is_fin("F.")
        assert not analyze_metrics._is_fin("P.")


# --------------------------------------------------------------------------- #
# output_format tests (C2)
# --------------------------------------------------------------------------- #

class TestOutputFormat:
    def test_output_format_client_metric_lines(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(), txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode == 0, f"stderr: {result.stderr}"

        metrics = _parse_metric_lines(result.stdout)
        assert "fct" in metrics, f"fct not found:\n{result.stdout}"
        assert "send_unlock" in metrics, f"send_unlock not found:\n{result.stdout}"
        for name in ("fct", "send_unlock"):
            m = metrics[name]
            assert m["node"] == "client"
            float(m["value_ms"])
            assert "flow" in m

    def test_output_format_flow_field(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(), txt)
        result = _run_analyzer(["--client-text", txt])
        flow = _parse_metric_lines(result.stdout)["fct"]["flow"]
        left, right = flow.split("-", 1)
        assert ":" in left and ":" in right

    def test_output_format_send_unlock_less_than_fct(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        result = _run_analyzer(["--client-text", txt])
        m = _parse_metric_lines(result.stdout)
        assert float(m["send_unlock"]["value_ms"]) <= float(m["fct"]["value_ms"])

    def test_output_format_metric_values_correct(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(t0=1000.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        m = _parse_metric_lines(result.stdout)
        assert abs(float(m["send_unlock"]["value_ms"]) - 100.0) < 1.0
        assert abs(float(m["fct"]["value_ms"]) - 150.0) < 1.0

    def test_output_format_server_gap(self, tmp_path):
        ctxt = str(tmp_path / "client.txt")
        stxt = str(tmp_path / "server.txt")
        _write_text(_build_client_text(), ctxt)
        _write_text(_build_server_text(syn_ack_delay_ms=5.0, payload_delay_ms=100.0), stxt)
        result = _run_analyzer(["--client-text", ctxt, "--server-text", stxt])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        m = _parse_metric_lines(result.stdout)
        assert "server_gap" in m, f"server_gap not in output:\n{result.stdout}"
        assert m["server_gap"]["node"] == "server"
        # server_gap = payload_delay - syn_ack_delay = 100 - 5 = 95ms
        assert abs(float(m["server_gap"]["value_ms"]) - 95.0) < 1.0

    def test_multiple_flows_emit_per_flow(self, tmp_path):
        lines = _build_client_text(t0=0.0)
        # second flow on a different client port
        lines += [
            _td(0.0, CLIENT_IP, 54322, SERVER_IP, SERVER_PORT, "S", 0),
            _td(0.005, SERVER_IP, SERVER_PORT, CLIENT_IP, 54322, "S.", 0),
            _td(0.100, CLIENT_IP, 54322, SERVER_IP, SERVER_PORT, "P.", 11),
            _td(0.150, CLIENT_IP, 54322, SERVER_IP, SERVER_PORT, "F.", 0),
        ]
        txt = str(tmp_path / "two.txt")
        _write_text(lines, txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode == 0
        # two send_unlock + two fct lines
        su = [l for l in result.stdout.splitlines() if l.startswith("metric=send_unlock")]
        fct = [l for l in result.stdout.splitlines() if l.startswith("metric=fct")]
        assert len(su) == 2 and len(fct) == 2


# --------------------------------------------------------------------------- #
# guardrails tests (C3)
# --------------------------------------------------------------------------- #

class TestGuardrails:
    def test_guardrails_empty_capture_exits_nonzero(self, tmp_path):
        txt = str(tmp_path / "empty.txt")
        Path(txt).write_text("")
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode != 0
        assert "empty_capture" in _parse_missing_lines(result.stdout)

    def test_guardrails_only_garbage_lines_exits_nonzero(self, tmp_path):
        txt = str(tmp_path / "garbage.txt")
        Path(txt).write_text("not a packet\nARP foo\n\n")
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode != 0

    def test_guardrails_no_syn_emits_missing_and_exits_nonzero(self, tmp_path):
        txt = str(tmp_path / "no_syn.txt")
        # only a SYN-ACK, no SYN
        _write_text([_td(0.0, SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT, "S.", 0)], txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode != 0
        assert "SYN" in _parse_missing_lines(result.stdout)

    def test_guardrails_no_payload_emits_missing(self, tmp_path):
        txt = str(tmp_path / "no_payload.txt")
        _write_text(_build_client_text(include_payload=False, include_fin=False), txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode != 0
        assert len(_parse_missing_lines(result.stdout)) > 0

    def test_guardrails_server_no_syn_ack_exits_nonzero(self, tmp_path):
        ctxt = str(tmp_path / "client.txt")
        stxt = str(tmp_path / "server.txt")
        _write_text(_build_client_text(), ctxt)
        # server pcap with only inbound data, no SYN-ACK
        _write_text([_td(0.1, CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT, "P.", 11)], stxt)
        result = _run_analyzer(["--client-text", ctxt, "--server-text", stxt])
        assert result.returncode != 0
        assert "SYN-ACK" in _parse_missing_lines(result.stdout)

    def test_guardrails_server_no_inbound_payload_exits_nonzero(self, tmp_path):
        ctxt = str(tmp_path / "client.txt")
        stxt = str(tmp_path / "server.txt")
        _write_text(_build_client_text(), ctxt)
        _write_text(_build_server_text(include_inbound_payload=False), stxt)
        result = _run_analyzer(["--client-text", ctxt, "--server-text", stxt])
        assert result.returncode != 0
        assert "first_inbound_payload" in _parse_missing_lines(result.stdout)

    def test_guardrails_no_input_exits_nonzero(self):
        result = _run_analyzer([])
        assert result.returncode != 0


# --------------------------------------------------------------------------- #
# cross_check tests (C4)
# --------------------------------------------------------------------------- #

class TestCrossCheck:
    def _write_iperf_csv(self, path: str, duration_s: float) -> None:
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([
                "20230101120000", CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                "1", f"0.0-{duration_s:.3f}", "1048576", "104857600",
            ])

    def test_cross_check_no_warning_within_threshold(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.155)  # within 10ms of 150ms
        result = _run_analyzer(["--client-text", txt, "--iperf-csv", csv_path])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        assert "WARNING" not in result.stderr

    def test_cross_check_warning_when_diverges(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.200)  # 50ms divergence
        result = _run_analyzer(["--client-text", txt, "--iperf-csv", csv_path])
        assert result.returncode == 0
        assert "WARNING" in result.stderr
        assert "10 ms" in result.stderr or "threshold" in result.stderr

    def test_cross_check_pcap_authoritative(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.500)
        result = _run_analyzer(["--client-text", txt, "--iperf-csv", csv_path])
        fct_ms = float(_parse_metric_lines(result.stdout)["fct"]["value_ms"])
        assert abs(fct_ms - 150.0) < 1.0

    def test_cross_check_no_csv_no_cross_check(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(), txt)
        result = _run_analyzer(["--client-text", txt])
        assert result.returncode == 0
        assert "WARNING" not in result.stderr

    def test_cross_check_within_boundary(self, tmp_path):
        txt = str(tmp_path / "client.txt")
        _write_text(_build_client_text(syn_to_payload_ms=100.0, payload_to_fin_ms=50.0), txt)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.160)  # exactly 10ms
        result = _run_analyzer(["--client-text", txt, "--iperf-csv", csv_path])
        assert result.returncode == 0
        assert "WARNING" not in result.stderr

    def test_parse_iperf_csv_duration_direct(self, tmp_path):
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.150)
        assert abs(analyze_metrics.parse_iperf_csv_duration(csv_path) - 150.0) < 0.001


# --------------------------------------------------------------------------- #
# --summary / --detail-out tests
#
# Regression cover for the SSM 24 KB StandardOutputContent truncation: the
# per-flow format cost ~170 bytes/flow, so a 68,779-flow run was silently cut to
# its first 144 flows mid-line. Summary output must stay constant-size.
# --------------------------------------------------------------------------- #

def _build_n_flows(n: int, t0: float = 1000.0) -> list:
    """n independent client flows, each with a distinct send_unlock delay."""
    lines = []
    for i in range(n):
        sport = 20000 + i
        t = t0 + i * 0.001
        lines += [
            _td(t, CLIENT_IP, sport, SERVER_IP, SERVER_PORT, "S", 0),
            _td(t + 0.005, SERVER_IP, SERVER_PORT, CLIENT_IP, sport, "S.", 0),
            _td(t + 0.010 + i * 0.001, CLIENT_IP, sport, SERVER_IP, SERVER_PORT, "P.", 11),
            _td(t + 0.100, CLIENT_IP, sport, SERVER_IP, SERVER_PORT, "F.", 0),
        ]
    return lines


def _parse_summary_lines(stdout: str) -> dict:
    """Parse `summary=<name> node=.. n=.. ...` lines into {name: {field: value}}."""
    out = {}
    for line in stdout.splitlines():
        if not line.startswith("summary="):
            continue
        fields = dict(kv.split("=", 1) for kv in line.split() if "=" in kv)
        out[fields.pop("summary")] = fields
    return out


class TestSummaryMode:
    def test_summary_output_is_constant_size_across_scales(self, tmp_path):
        """The whole point: 10 flows and 1000 flows produce the same output size."""
        small = str(tmp_path / "small.txt")
        large = str(tmp_path / "large.txt")
        _write_text(_build_n_flows(10), small)
        _write_text(_build_n_flows(1000), large)

        out_small = _run_analyzer(["--client-text", small, "--summary"]).stdout
        out_large = _run_analyzer(["--client-text", large, "--summary"]).stdout

        assert len(out_small.splitlines()) == len(out_large.splitlines())
        # Comfortably under SSM's 24 KB cap at 100x the flow count.
        assert len(out_large) < 1024, f"summary grew to {len(out_large)} bytes"

    def test_summary_reports_every_flow_not_a_prefix(self, tmp_path):
        """n= must equal the true flow count - the bug reported 144 of 68,779."""
        txt = str(tmp_path / "many.txt")
        _write_text(_build_n_flows(500), txt)
        s = _parse_summary_lines(_run_analyzer(["--client-text", txt, "--summary"]).stdout)
        assert s["send_unlock"]["n"] == "500"
        assert s["fct"]["n"] == "500"

    def test_summary_percentiles_are_ordered(self, tmp_path):
        txt = str(tmp_path / "many.txt")
        _write_text(_build_n_flows(200), txt)
        f = _parse_summary_lines(
            _run_analyzer(["--client-text", txt, "--summary"]).stdout)["send_unlock"]
        vals = [float(f[k]) for k in ("min_ms", "p50_ms", "p95_ms", "p99_ms", "max_ms")]
        assert vals == sorted(vals), f"percentiles out of order: {vals}"

    def test_summary_values_match_known_distribution(self, tmp_path):
        """send_unlock spans 10ms..(10+n-1)ms in 1ms steps; check min/max/p50."""
        txt = str(tmp_path / "many.txt")
        _write_text(_build_n_flows(101), txt)
        f = _parse_summary_lines(
            _run_analyzer(["--client-text", txt, "--summary"]).stdout)["send_unlock"]
        assert abs(float(f["min_ms"]) - 10.0) < 0.5
        assert abs(float(f["max_ms"]) - 110.0) < 0.5
        assert abs(float(f["p50_ms"]) - 60.0) < 0.5

    def test_summary_single_flow_does_not_crash(self, tmp_path):
        """percentile() must handle n=1, which statistics.quantiles() rejects."""
        txt = str(tmp_path / "one.txt")
        _write_text(_build_client_text(), txt)
        result = _run_analyzer(["--client-text", txt, "--summary"])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        f = _parse_summary_lines(result.stdout)["fct"]
        assert f["n"] == "1"
        assert f["min_ms"] == f["p50_ms"] == f["max_ms"]

    def test_summary_aggregates_missing_events_with_count(self, tmp_path):
        """Missing events collapse to one counted line, not one line per flow."""
        # Flows that SYN but never send a payload or FIN.
        lines = []
        for i in range(50):
            sport = 30000 + i
            lines.append(_td(1000.0 + i * 0.001, CLIENT_IP, sport, SERVER_IP, SERVER_PORT, "S", 0))
        txt = str(tmp_path / "stalled.txt")
        _write_text(lines, txt)
        result = _run_analyzer(["--client-text", txt, "--summary"])
        assert result.returncode != 0
        missing = [l for l in result.stdout.splitlines() if l.startswith("missing=")]
        assert len(missing) == 2, f"expected 2 aggregated lines, got:\n{result.stdout}"
        assert all("count=50" in l for l in missing), missing

    def test_summary_server_gap_node_tagged(self, tmp_path):
        ctxt = str(tmp_path / "c.txt")
        stxt = str(tmp_path / "s.txt")
        _write_text(_build_client_text(), ctxt)
        _write_text(_build_server_text(syn_ack_delay_ms=5.0, payload_delay_ms=100.0), stxt)
        out = _run_analyzer(
            ["--client-text", ctxt, "--server-text", stxt, "--summary"]).stdout
        s = _parse_summary_lines(out)
        assert s["server_gap"]["node"] == "server"
        assert s["fct"]["node"] == "client"
        assert abs(float(s["server_gap"]["p50_ms"]) - 95.0) < 1.0


class TestDetailOut:
    def test_detail_out_keeps_full_per_flow_data(self, tmp_path):
        """Bounded on the wire, complete on disk - no data is actually lost."""
        txt = str(tmp_path / "many.txt")
        detail = tmp_path / "detail.txt"
        _write_text(_build_n_flows(300), txt)
        result = _run_analyzer(
            ["--client-text", txt, "--summary", "--detail-out", str(detail)])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        written = detail.read_text().splitlines()
        assert len([l for l in written if l.startswith("metric=send_unlock")]) == 300
        assert len([l for l in written if l.startswith("metric=fct")]) == 300
        # stdout stayed small while the detail file holds everything
        assert len(result.stdout) < 1024

    def test_detail_out_without_summary_still_writes(self, tmp_path):
        txt = str(tmp_path / "one.txt")
        detail = tmp_path / "detail.txt"
        _write_text(_build_client_text(), txt)
        _run_analyzer(["--client-text", txt, "--detail-out", str(detail)])
        assert "metric=fct" in detail.read_text()

    def test_detail_out_unwritable_path_exits_nonzero(self, tmp_path):
        txt = str(tmp_path / "one.txt")
        _write_text(_build_client_text(), txt)
        bad = str(tmp_path / "no_such_dir" / "detail.txt")
        result = _run_analyzer(["--client-text", txt, "--detail-out", bad])
        assert result.returncode != 0
        assert "detail-out" in result.stderr


class TestPerFlowTruncationWarning:
    def test_large_per_flow_run_warns_about_output_caps(self, tmp_path):
        txt = str(tmp_path / "many.txt")
        _write_text(_build_n_flows(200), txt)
        result = _run_analyzer(["--client-text", txt])
        assert "24 KB" in result.stderr, f"no truncation warning:\n{result.stderr}"
        assert "--summary" in result.stderr

    def test_small_per_flow_run_does_not_warn(self, tmp_path):
        txt = str(tmp_path / "one.txt")
        _write_text(_build_client_text(), txt)
        result = _run_analyzer(["--client-text", txt])
        assert "WARNING" not in result.stderr

    def test_summary_mode_never_warns(self, tmp_path):
        txt = str(tmp_path / "many.txt")
        _write_text(_build_n_flows(200), txt)
        result = _run_analyzer(["--client-text", txt, "--summary"])
        assert "WARNING" not in result.stderr


class TestPercentileUnit:
    def test_percentile_single_value(self):
        assert analyze_metrics.percentile([42.0], 50) == 42.0
        assert analyze_metrics.percentile([42.0], 99) == 42.0

    def test_percentile_known_values(self):
        vals = [float(i) for i in range(1, 101)]  # 1..100
        assert abs(analyze_metrics.percentile(vals, 50) - 50.5) < 0.01
        assert abs(analyze_metrics.percentile(vals, 0) - 1.0) < 0.01
        assert abs(analyze_metrics.percentile(vals, 100) - 100.0) < 0.01

    def test_percentile_empty_raises(self):
        with pytest.raises(ValueError):
            analyze_metrics.percentile([], 50)
