"""
Unit tests for experiments/utils/analyze_metrics.py

Builds synthetic TCP flows with scapy, writes them to temp pcap files,
and asserts metric values, key=value output format, guardrail behavior,
and iperf CSV cross-check.

No DPDK or live infrastructure required.
"""

import csv
import io
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import List, Optional

import pytest

# Scapy imports — the tests construct synthetic packets
from scapy.all import Ether, IP, TCP, wrpcap

# Locate the analyzer script relative to this test file:
# tests/ -> utils/ -> analyze_metrics.py
_UTILS_DIR = Path(__file__).parent.parent
_ANALYZER = str(_UTILS_DIR / "analyze_metrics.py")

# Suppress WinPcap deprecation warning noise in captured output
_ENV = os.environ.copy()
_ENV.setdefault("PYTHONWARNINGS", "ignore")


# --------------------------------------------------------------------------- #
# Packet / pcap builders
# --------------------------------------------------------------------------- #

def _pkt(src_ip: str, src_port: int, dst_ip: str, dst_port: int,
         flags: str, seq: int = 1000, ack: int = 0, payload: bytes = b"",
         ts: float = 0.0):
    """Build an Ethernet/IP/TCP packet with an explicit pcap timestamp."""
    p = (
        Ether(src="aa:bb:cc:dd:ee:01", dst="aa:bb:cc:dd:ee:02")
        / IP(src=src_ip, dst=dst_ip)
        / TCP(sport=src_port, dport=dst_port, flags=flags, seq=seq, ack=ack)
        / payload
    )
    p.time = ts
    return p


def _write_pcap(pkts, path: str) -> None:
    wrpcap(path, pkts)


CLIENT_IP = "10.0.0.1"
CLIENT_PORT = 54321
SERVER_IP = "10.0.0.2"
SERVER_PORT = 5001


def _build_client_flow(
    t0: float = 0.0,
    syn_to_payload_ms: float = 100.0,
    payload_to_fin_ms: float = 50.0,
    include_syn: bool = True,
    include_payload: bool = True,
    include_fin: bool = True,
) -> List:
    """
    Build a minimal client-side pcap packet list:
      t0+0ms     : SYN    (client → server)
      t0+0ms     : SYN-ACK (server → client, spoofed/real, same timing)
      t0+syn_to_payload_ms: DATA (client → server, payload>0)
      t0+syn_to_payload_ms+payload_to_fin_ms: FIN (client → server)
    """
    pkts = []
    if include_syn:
        pkts.append(_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                         "S", seq=1000, ack=0, ts=t0))
        # SYN-ACK back (server→client)
        pkts.append(_pkt(SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT,
                         "SA", seq=2000, ack=1001, ts=t0 + 0.005))
    if include_payload:
        t_payload = t0 + syn_to_payload_ms / 1000.0
        pkts.append(_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                         "PA", seq=1001, ack=2001, payload=b"hello world",
                         ts=t_payload))
    if include_fin:
        t_fin = t0 + (syn_to_payload_ms + payload_to_fin_ms) / 1000.0
        pkts.append(_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                         "FA", seq=1012, ack=2001, ts=t_fin))
    return pkts


def _build_server_flow(
    t0: float = 0.0,
    syn_ack_delay_ms: float = 5.0,
    payload_delay_ms: float = 100.0,
    include_syn_ack: bool = True,
    include_inbound_payload: bool = True,
) -> List:
    """
    Build a minimal server-side pcap packet list:
      t0+0ms            : SYN    (client → server, arrives at server host)
      t0+syn_ack_delay  : SYN-ACK (server → client)
      t0+payload_delay  : DATA (client → server, payload>0)
    """
    pkts = []
    # SYN arrives at server
    pkts.append(_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                     "S", seq=1000, ts=t0))
    if include_syn_ack:
        t_sa = t0 + syn_ack_delay_ms / 1000.0
        pkts.append(_pkt(SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT,
                         "SA", seq=2000, ack=1001, ts=t_sa))
    if include_inbound_payload:
        t_data = t0 + payload_delay_ms / 1000.0
        pkts.append(_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                         "PA", seq=1001, ack=2001, payload=b"hello world",
                         ts=t_data))
    return pkts


# --------------------------------------------------------------------------- #
# Helpers for running the analyzer
# --------------------------------------------------------------------------- #

def _run_analyzer(args: List[str]) -> subprocess.CompletedProcess:
    result = subprocess.run(
        [sys.executable, _ANALYZER] + args,
        capture_output=True,
        text=True,
        env=_ENV,
    )
    # Strip platform noise (WinPcap deprecation warning) from stderr so tests are portable
    filtered_lines = [
        line for line in result.stderr.splitlines()
        if "WinPcap" not in line and "Npcap" not in line
    ]
    # Replace stderr with filtered version (CompletedProcess is a simple namedtuple-like object)
    result = subprocess.CompletedProcess(
        args=result.args,
        returncode=result.returncode,
        stdout=result.stdout,
        stderr="\n".join(filtered_lines) + ("\n" if filtered_lines else ""),
    )
    return result


def _parse_metric_lines(stdout: str) -> dict:
    """Parse all metric=... key=value lines from stdout into a dict keyed by metric name."""
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
    """Return list of missing=<event> values from stdout."""
    missing = []
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("missing="):
            token = line.split()[0]
            _, event = token.split("=", 1)
            missing.append(event)
    return missing


# --------------------------------------------------------------------------- #
# output_format tests (C2)
# --------------------------------------------------------------------------- #

class TestOutputFormat:
    """Tests for the key=value metric output format (C2)."""

    def test_output_format_client_metric_lines(self, tmp_path):
        """Each metric line matches: metric=<name> value_ms=<v> node=<n> flow=<f>"""
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode == 0, f"stderr: {result.stderr}"

        metrics = _parse_metric_lines(result.stdout)
        assert "fct" in metrics, f"fct not found in output:\n{result.stdout}"
        assert "send_unlock" in metrics, f"send_unlock not found in output:\n{result.stdout}"

        for name in ("fct", "send_unlock"):
            m = metrics[name]
            assert "value_ms" in m, f"value_ms missing for {name}"
            assert "node" in m, f"node missing for {name}"
            assert "flow" in m, f"flow missing for {name}"
            assert m["node"] == "client", f"node should be 'client' for {name}"
            # value_ms must be parseable as float
            float(m["value_ms"])

    def test_output_format_flow_field(self, tmp_path):
        """flow field is srcip:sport-dstip:dport format."""
        pkts = _build_client_flow(t0=0.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        metrics = _parse_metric_lines(result.stdout)
        assert "fct" in metrics
        flow = metrics["fct"]["flow"]
        # format: srcip:sport-dstip:dport
        assert "-" in flow, f"expected '-' separator in flow: {flow}"
        left, right = flow.split("-", 1)
        assert ":" in left, f"expected ':' in flow left part: {left}"
        assert ":" in right, f"expected ':' in flow right part: {right}"

    def test_output_format_send_unlock_less_than_fct(self, tmp_path):
        """send_unlock value_ms <= fct value_ms (same client pcap source of truth)."""
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode == 0
        metrics = _parse_metric_lines(result.stdout)
        fct_ms = float(metrics["fct"]["value_ms"])
        su_ms = float(metrics["send_unlock"]["value_ms"])
        assert su_ms <= fct_ms, f"send_unlock ({su_ms}) should be <= fct ({fct_ms})"

    def test_output_format_metric_values_correct(self, tmp_path):
        """Computed metric values are within 1ms of expected synthetic values."""
        t0 = 1000.0  # arbitrary epoch offset
        syn_to_payload_ms = 100.0
        payload_to_fin_ms = 50.0
        pkts = _build_client_flow(
            t0=t0,
            syn_to_payload_ms=syn_to_payload_ms,
            payload_to_fin_ms=payload_to_fin_ms,
        )
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        metrics = _parse_metric_lines(result.stdout)

        su_ms = float(metrics["send_unlock"]["value_ms"])
        fct_ms = float(metrics["fct"]["value_ms"])
        expected_fct = syn_to_payload_ms + payload_to_fin_ms

        assert abs(su_ms - syn_to_payload_ms) < 1.0, (
            f"send_unlock expected ~{syn_to_payload_ms}ms, got {su_ms:.3f}ms"
        )
        assert abs(fct_ms - expected_fct) < 1.0, (
            f"fct expected ~{expected_fct}ms, got {fct_ms:.3f}ms"
        )

    def test_output_format_server_gap(self, tmp_path):
        """server_gap metric is emitted with node=server when server pcap provided."""
        cpkts = _build_client_flow(t0=0.0)
        cpcap = str(tmp_path / "client.pcap")
        _write_pcap(cpkts, cpcap)

        spkts = _build_server_flow(t0=0.0, syn_ack_delay_ms=5.0, payload_delay_ms=100.0)
        spcap = str(tmp_path / "server.pcap")
        _write_pcap(spkts, spcap)

        result = _run_analyzer(["--client-pcap", cpcap, "--server-pcap", spcap])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        metrics = _parse_metric_lines(result.stdout)
        assert "server_gap" in metrics, f"server_gap not in output:\n{result.stdout}"
        assert metrics["server_gap"]["node"] == "server"
        sg_ms = float(metrics["server_gap"]["value_ms"])
        # server_gap = payload_delay - syn_ack_delay = 100 - 5 = 95ms
        assert abs(sg_ms - 95.0) < 1.0, f"server_gap expected ~95ms, got {sg_ms:.3f}ms"


# --------------------------------------------------------------------------- #
# guardrails tests (C3)
# --------------------------------------------------------------------------- #

class TestGuardrails:
    """Tests for incomplete-capture validation guardrails (C3)."""

    def test_guardrails_empty_file_exits_nonzero(self, tmp_path):
        """An empty file causes non-zero exit."""
        empty = str(tmp_path / "empty.pcap")
        Path(empty).write_bytes(b"")
        result = _run_analyzer(["--client-pcap", empty])
        assert result.returncode != 0, "expected non-zero exit for empty pcap"

    def test_guardrails_no_syn_emits_missing_and_exits_nonzero(self, tmp_path):
        """A pcap with no SYN emits missing=SYN and exits non-zero."""
        # Only a SYN-ACK, no SYN
        pkts = [_pkt(SERVER_IP, SERVER_PORT, CLIENT_IP, CLIENT_PORT,
                     "SA", seq=2000, ack=1001, ts=0.0)]
        pcap = str(tmp_path / "no_syn.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode != 0, "expected non-zero exit when no SYN"
        missing = _parse_missing_lines(result.stdout)
        assert "SYN" in missing, f"expected missing=SYN in output:\n{result.stdout}"

    def test_guardrails_no_payload_emits_missing_and_exits_nonzero(self, tmp_path):
        """A pcap with SYN but no payload segment emits missing flag and exits non-zero."""
        pkts = _build_client_flow(include_payload=False, include_fin=False)
        pcap = str(tmp_path / "no_payload.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode != 0, "expected non-zero exit when no payload"
        missing = _parse_missing_lines(result.stdout)
        assert len(missing) > 0, f"expected at least one missing= line:\n{result.stdout}"

    def test_guardrails_no_fin_no_data_exits_nonzero(self, tmp_path):
        """SYN-only capture (no data, no FIN) exits non-zero."""
        pkts = _build_client_flow(include_payload=False, include_fin=False)
        pcap = str(tmp_path / "syn_only.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode != 0

    def test_guardrails_server_no_syn_ack_exits_nonzero(self, tmp_path):
        """Server pcap missing SYN-ACK emits missing=SYN-ACK and exits non-zero."""
        cpkts = _build_client_flow()
        cpcap = str(tmp_path / "client.pcap")
        _write_pcap(cpkts, cpcap)

        # Server pcap with only inbound data, no SYN-ACK
        spkts = [_pkt(CLIENT_IP, CLIENT_PORT, SERVER_IP, SERVER_PORT,
                      "PA", seq=1001, payload=b"hello", ts=0.1)]
        spcap = str(tmp_path / "server.pcap")
        _write_pcap(spkts, spcap)

        result = _run_analyzer(["--client-pcap", cpcap, "--server-pcap", spcap])
        assert result.returncode != 0
        missing = _parse_missing_lines(result.stdout)
        assert "SYN-ACK" in missing, f"expected missing=SYN-ACK:\n{result.stdout}"

    def test_guardrails_server_no_inbound_payload_exits_nonzero(self, tmp_path):
        """Server pcap with SYN-ACK but no inbound payload exits non-zero."""
        cpkts = _build_client_flow()
        cpcap = str(tmp_path / "client.pcap")
        _write_pcap(cpkts, cpcap)

        spkts = _build_server_flow(include_inbound_payload=False)
        spcap = str(tmp_path / "server_no_data.pcap")
        _write_pcap(spkts, spcap)

        result = _run_analyzer(["--client-pcap", cpcap, "--server-pcap", spcap])
        assert result.returncode != 0
        missing = _parse_missing_lines(result.stdout)
        assert "first_inbound_payload" in missing, (
            f"expected missing=first_inbound_payload:\n{result.stdout}"
        )

    def test_guardrails_truncated_pcap_exits_nonzero(self, tmp_path):
        """A truncated (corrupted) pcap file causes non-zero exit."""
        # Write a valid pcap header then truncate it with garbage
        truncated = str(tmp_path / "truncated.pcap")
        Path(truncated).write_bytes(b"\xd4\xc3\xb2\xa1" + b"\x00" * 4)  # partial header
        result = _run_analyzer(["--client-pcap", truncated])
        assert result.returncode != 0, "expected non-zero exit for truncated pcap"


# --------------------------------------------------------------------------- #
# cross_check tests (C4)
# --------------------------------------------------------------------------- #

class TestCrossCheck:
    """Tests for iperf CSV FCT cross-check (C4)."""

    def _write_iperf_csv(self, path: str, duration_s: float) -> None:
        """Write a minimal iperf2 -yC CSV with given duration."""
        with open(path, "w", newline="") as f:
            writer = csv.writer(f)
            # Format: timestamp,src_ip,src_port,dst_ip,dst_port,transfer_id,interval,transfer,bandwidth
            writer.writerow([
                "20230101120000",
                CLIENT_IP, CLIENT_PORT,
                SERVER_IP, SERVER_PORT,
                "1",
                f"0.0-{duration_s:.3f}",
                "1048576",
                "104857600",
            ])

    def test_cross_check_no_warning_within_threshold(self, tmp_path):
        """No warning when pcap FCT and iperf CSV agree within 10ms."""
        # fct = 150ms (syn_to_payload=100 + payload_to_fin=50)
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        # iperf says 155ms (within 10ms threshold)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.155)

        result = _run_analyzer(["--client-pcap", pcap, "--iperf-csv", csv_path])
        assert result.returncode == 0, f"stderr: {result.stderr}"
        assert "WARNING" not in result.stderr, (
            f"unexpected warning in stderr:\n{result.stderr}"
        )

    def test_cross_check_warning_when_diverges(self, tmp_path):
        """Warning is emitted to stderr when divergence > 10ms."""
        # fct = 150ms
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        # iperf says 200ms (50ms divergence > 10ms threshold)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.200)

        result = _run_analyzer(["--client-pcap", pcap, "--iperf-csv", csv_path])
        # pcap result is still authoritative (non-zero exit only if missing events)
        assert result.returncode == 0, f"returncode should be 0 (pcap is fine)"
        assert "WARNING" in result.stderr, (
            f"expected divergence warning in stderr:\n{result.stderr}"
        )
        assert "10 ms" in result.stderr or "threshold" in result.stderr, (
            f"warning should mention threshold:\n{result.stderr}"
        )

    def test_cross_check_pcap_authoritative(self, tmp_path):
        """pcap-derived FCT value is the one emitted even when CSV diverges."""
        # fct = 150ms
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        # iperf says 500ms (huge divergence)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.500)

        result = _run_analyzer(["--client-pcap", pcap, "--iperf-csv", csv_path])
        metrics = _parse_metric_lines(result.stdout)
        assert "fct" in metrics
        fct_ms = float(metrics["fct"]["value_ms"])
        # pcap says ~150ms — must not be 500ms
        assert abs(fct_ms - 150.0) < 1.0, (
            f"pcap value should be authoritative (~150ms), got {fct_ms:.3f}ms"
        )

    def test_cross_check_no_csv_no_cross_check(self, tmp_path):
        """When --iperf-csv not provided, analyzer runs fine with no warning."""
        pkts = _build_client_flow(t0=0.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        result = _run_analyzer(["--client-pcap", pcap])
        assert result.returncode == 0
        assert "WARNING" not in result.stderr

    def test_cross_check_within_boundary(self, tmp_path):
        """Divergence exactly at threshold boundary: no warning at <=10ms."""
        # fct = 150ms
        pkts = _build_client_flow(t0=0.0, syn_to_payload_ms=100.0, payload_to_fin_ms=50.0)
        pcap = str(tmp_path / "client.pcap")
        _write_pcap(pkts, pcap)

        # iperf says exactly 160ms (10ms divergence = boundary, should NOT warn)
        csv_path = str(tmp_path / "iperf.csv")
        self._write_iperf_csv(csv_path, duration_s=0.160)

        result = _run_analyzer(["--client-pcap", pcap, "--iperf-csv", csv_path])
        assert result.returncode == 0
        assert "WARNING" not in result.stderr, (
            f"should not warn at exactly 10ms boundary:\n{result.stderr}"
        )
