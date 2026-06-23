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
