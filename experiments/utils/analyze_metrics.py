#!/usr/bin/env python3
"""
Offline pcap analyzer for 0-RTT endpoint metrics — tcpdump-based (no scapy).

Computes three metrics by streaming `tcpdump -r <pcap>` text output. tcpdump is
a C tool already present on every capture host; parsing its line-oriented output
one packet at a time keeps memory flat (O(flows), not O(packets)), so it handles
the 20-40 MB / 200k-packet endpoint captures the experiment produces without the
multi-GB RAM blow-up of loading a whole pcap into Python objects.

  fct         — Flow Completion Time: first SYN out → last data byte or FIN (client pcap)
  send_unlock — Time to first payload: first SYN out → first outbound payload>0 segment (client pcap)
  server_gap  — Server-side gap: first SYN-ACK out → first inbound payload>0 segment (server pcap)

Output format (machine-parseable key=value lines):
  metric=fct          value_ms=<v> node=client flow=<srcip:sport-dstip:dport>
  metric=send_unlock  value_ms=<v> node=client flow=<...>
  metric=server_gap   value_ms=<v> node=server flow=<...>

Missing events produce a flag line and non-zero exit:
  missing=<event_name> flow=<...>

Usage:
    python3 analyze_metrics.py --client-pcap /tmp/client.pcap
    python3 analyze_metrics.py --client-pcap /tmp/client.pcap --server-pcap /tmp/server.pcap
    python3 analyze_metrics.py --client-pcap /tmp/client.pcap --iperf-csv /tmp/iperf.csv

For testing on hosts without tcpdump, pre-captured `tcpdump -r ... -nn -tt`
text can be fed directly via --client-text / --server-text.
"""

import argparse
import csv
import re
import subprocess
import sys
from collections import namedtuple
from typing import List, Optional, Tuple

# A single parsed TCP/IP packet from tcpdump output.
Pkt = namedtuple("Pkt", "time src sport dst dport flags length")

# tcpdump default line for an IPv4 TCP segment, e.g.:
#   1624363200.123456 IP 10.0.0.1.54321 > 10.0.0.2.5001: Flags [S.], seq 1, ack 1, win 0, length 1460
_LINE_RE = re.compile(
    r"^(?P<t>\d+\.\d+)\s+IP\s+"
    r"(?P<sip>\d{1,3}(?:\.\d{1,3}){3})\.(?P<sport>\d+)\s+>\s+"
    r"(?P<dip>\d{1,3}(?:\.\d{1,3}){3})\.(?P<dport>\d+):\s+"
    r"Flags\s+\[(?P<flags>[^\]]*)\]"
    r".*\blength\s+(?P<length>\d+)"
)


# --------------------------------------------------------------------------- #
# Parsing
# --------------------------------------------------------------------------- #

def parse_line(line: str) -> Optional[Pkt]:
    """Parse one `tcpdump -nn -tt` line into a Pkt, or None if it isn't an IPv4 TCP line."""
    m = _LINE_RE.match(line)
    if not m:
        return None
    return Pkt(
        time=float(m.group("t")),
        src=m.group("sip"),
        sport=int(m.group("sport")),
        dst=m.group("dip"),
        dport=int(m.group("dport")),
        flags=m.group("flags"),
        length=int(m.group("length")),
    )


def _is_syn(flags: str) -> bool:
    # tcpdump: SYN = [S], SYN-ACK = [S.]  ('.' denotes ACK)
    return "S" in flags and "." not in flags


def _is_syn_ack(flags: str) -> bool:
    return "S" in flags and "." in flags


def _is_fin(flags: str) -> bool:
    return "F" in flags


def _canon(p: Pkt) -> tuple:
    """Direction-independent flow key (4-tuple of the two endpoints, sorted)."""
    a = (p.src, p.sport, p.dst, p.dport)
    b = (p.dst, p.dport, p.src, p.sport)
    return a if a <= b else b


# --------------------------------------------------------------------------- #
# Streaming analysis (single pass, O(flows) memory)
# --------------------------------------------------------------------------- #

def analyze_client(records) -> Tuple[Optional[str], list]:
    """
    Compute send_unlock and fct for every client-side flow (one per SYN 4-tuple).
    Returns (first_flow_str_or_None, flat_list_of_metric_and_error_dicts).
    """
    flows: dict = {}
    order: list = []
    for p in records:
        key = _canon(p)
        if _is_syn(p.flags):
            if key not in flows:
                flows[key] = {
                    "client": (p.src, p.sport),
                    "t_syn": p.time,
                    "first_payload": None,
                    "last_data": None,
                    "flow": f"{p.src}:{p.sport}-{p.dst}:{p.dport}",
                }
                order.append(key)
            continue
        f = flows.get(key)
        if f is None:
            continue
        c2s = (p.src, p.sport) == f["client"]
        has_payload = p.length > 0
        if c2s and has_payload and f["first_payload"] is None:
            f["first_payload"] = p.time
        if has_payload or _is_fin(p.flags):
            f["last_data"] = p.time

    if not order:
        return None, [{"kind": "missing", "event": "SYN", "flow": "unknown"}]

    results: list = []
    first_flow: Optional[str] = None
    for key in order:
        f = flows[key]
        if first_flow is None:
            first_flow = f["flow"]
        if f["first_payload"] is None:
            results.append({"kind": "missing", "event": "first_outbound_payload", "flow": f["flow"]})
        else:
            results.append({
                "kind": "metric", "name": "send_unlock",
                "value_ms": (f["first_payload"] - f["t_syn"]) * 1000.0,
                "node": "client", "flow": f["flow"],
            })
        if f["last_data"] is None:
            results.append({"kind": "missing", "event": "last_data_or_FIN", "flow": f["flow"]})
        else:
            results.append({
                "kind": "metric", "name": "fct",
                "value_ms": (f["last_data"] - f["t_syn"]) * 1000.0,
                "node": "client", "flow": f["flow"],
            })
    return first_flow, results


def analyze_server(records) -> Tuple[Optional[str], list]:
    """
    Compute server_gap for every server-side flow (one per SYN-ACK 4-tuple).
    Returns (first_flow_str_or_None, flat_list_of_results).
    """
    flows: dict = {}
    order: list = []
    for p in records:
        key = _canon(p)
        if _is_syn_ack(p.flags):
            if key not in flows:
                flows[key] = {
                    "server": (p.src, p.sport),
                    "client": (p.dst, p.dport),
                    "t_syn_ack": p.time,
                    "first_inbound": None,
                    "flow": f"{p.dst}:{p.dport}-{p.src}:{p.sport}",
                }
                order.append(key)
            continue
        f = flows.get(key)
        if f is None:
            continue
        if ((p.src, p.sport) == f["client"] and p.length > 0
                and f["first_inbound"] is None and p.time >= f["t_syn_ack"]):
            f["first_inbound"] = p.time

    if not order:
        return None, [{"kind": "missing", "event": "SYN-ACK", "flow": "unknown"}]

    results: list = []
    first_flow: Optional[str] = None
    for key in order:
        f = flows[key]
        if first_flow is None:
            first_flow = f["flow"]
        if f["first_inbound"] is None:
            results.append({"kind": "missing", "event": "first_inbound_payload", "flow": f["flow"]})
        else:
            results.append({
                "kind": "metric", "name": "server_gap",
                "value_ms": (f["first_inbound"] - f["t_syn_ack"]) * 1000.0,
                "node": "server", "flow": f["flow"],
            })
    return first_flow, results


# --------------------------------------------------------------------------- #
# Record sources
# --------------------------------------------------------------------------- #

def _records_from_pcap(path: str, counter: list):
    """Stream Pkt records by running tcpdump on a pcap. Raises RuntimeError on read failure."""
    argv = ["tcpdump", "-r", path, "-nn", "-tt", "-K"]
    try:
        proc = subprocess.Popen(
            argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
    except FileNotFoundError:
        raise RuntimeError("tcpdump not found in PATH")

    for line in proc.stdout:
        p = parse_line(line)
        if p is not None:
            counter[0] += 1
            yield p
    proc.stdout.close()
    rc = proc.wait()
    err = proc.stderr.read()
    proc.stderr.close()
    # Only treat a non-zero exit as fatal when nothing parsed — tcpdump can exit
    # non-zero on a truncated tail after already emitting valid packets.
    if rc not in (0,) and counter[0] == 0:
        raise RuntimeError(err.strip() or f"tcpdump exited {rc}")


def _records_from_text(path: str, counter: list):
    """Stream Pkt records from a file of pre-captured `tcpdump -nn -tt` text (testing)."""
    with open(path) as f:
        for line in f:
            p = parse_line(line)
            if p is not None:
                counter[0] += 1
                yield p


def _make_source(pcap: Optional[str], text: Optional[str]):
    """Return (record_generator, counter_list) for whichever input was given."""
    counter = [0]
    if text is not None:
        return _records_from_text(text, counter), counter
    return _records_from_pcap(pcap, counter), counter


# --------------------------------------------------------------------------- #
# iperf CSV cross-check
# --------------------------------------------------------------------------- #

def parse_iperf_csv_duration(csv_path: str) -> Optional[float]:
    """
    Parse an iperf2 -yC CSV file and return the reported transfer duration in ms.
    iperf2 CSV format (comma-separated):
      timestamp,src_ip,src_port,dst_ip,dst_port,transfer_id,interval,transfer,bandwidth
    The interval field is like "0.0-10.0" — duration = end - start.
    """
    try:
        with open(csv_path, newline="") as f:
            reader = csv.reader(f)
            max_duration_s = None
            for row in reader:
                if len(row) < 9:
                    continue
                interval = row[6].strip()
                if "-" not in interval:
                    continue
                try:
                    parts = interval.split("-")
                    start = float(parts[0])
                    end = float(parts[1])
                    duration = end - start
                    if max_duration_s is None or duration > max_duration_s:
                        max_duration_s = duration
                except ValueError:
                    continue
            if max_duration_s is not None:
                return max_duration_s * 1000.0
    except Exception as exc:
        print(f"WARNING: could not parse iperf CSV {csv_path}: {exc}", file=sys.stderr)
    return None


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #

def emit(result: dict) -> None:
    if result["kind"] == "metric":
        print(
            f"metric={result['name']}"
            f" value_ms={result['value_ms']:.3f}"
            f" node={result['node']}"
            f" flow={result['flow']}"
        )
    elif result["kind"] == "missing":
        print(
            f"missing={result['event']}"
            f" flow={result['flow']}"
        )


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Offline pcap analyzer for 0-RTT endpoint metrics (FCT, send-unlock, server-gap)."
    )
    parser.add_argument(
        "--client-pcap",
        default=None,
        help="Client-host pcap file (optional). Yields fct and send_unlock metrics.",
    )
    parser.add_argument(
        "--server-pcap",
        default=None,
        help="Server-host pcap file (optional). Yields server_gap metric.",
    )
    parser.add_argument(
        "--client-text",
        default=None,
        help=argparse.SUPPRESS,  # pre-captured `tcpdump -nn -tt` text (testing)
    )
    parser.add_argument(
        "--server-text",
        default=None,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--iperf-csv",
        default=None,
        help="iperf2 -yC CSV file (optional). Cross-checks pcap-derived FCT. "
             "Warns if divergence > 10 ms; pcap value remains authoritative.",
    )
    args = parser.parse_args()

    have_client = args.client_pcap is not None or args.client_text is not None
    have_server = args.server_pcap is not None or args.server_text is not None
    if not have_client and not have_server:
        print("ERROR: at least one of --client-pcap or --server-pcap is required",
              file=sys.stderr)
        return 2

    exit_code = 0
    fct_ms: Optional[float] = None

    # --- Client pcap (optional) ---
    if have_client:
        records, counter = _make_source(args.client_pcap, args.client_text)
        src = args.client_text or args.client_pcap
        try:
            _flow, client_results = analyze_client(records)
        except RuntimeError as exc:
            print(f"ERROR: cannot read {src}: {exc}", file=sys.stderr)
            return 1

        if counter[0] == 0:
            print("missing=empty_capture flow=unknown", flush=True)
            return 1

        for result in client_results:
            emit(result)
            if result["kind"] == "missing":
                exit_code = 1
            elif result["name"] == "fct":
                fct_ms = result["value_ms"]

    # --- Server pcap (optional) ---
    if have_server:
        records, counter = _make_source(args.server_pcap, args.server_text)
        src = args.server_text or args.server_pcap
        try:
            _sflow, server_results = analyze_server(records)
        except RuntimeError as exc:
            print(f"ERROR: cannot read {src}: {exc}", file=sys.stderr)
            return 1

        if counter[0] == 0:
            print("missing=empty_server_capture flow=unknown", flush=True)
            exit_code = 1
        else:
            for result in server_results:
                emit(result)
                if result["kind"] == "missing":
                    exit_code = 1

    # --- iperf CSV cross-check (advisory only) ---
    if args.iperf_csv is not None and fct_ms is not None:
        iperf_ms = parse_iperf_csv_duration(args.iperf_csv)
        if iperf_ms is not None:
            divergence = abs(fct_ms - iperf_ms)
            if divergence > 10.0:
                print(
                    f"WARNING: pcap FCT ({fct_ms:.3f} ms) diverges from iperf2 CSV "
                    f"({iperf_ms:.3f} ms) by {divergence:.3f} ms (threshold: 10 ms)",
                    file=sys.stderr,
                )
        else:
            print(
                f"WARNING: could not extract duration from iperf CSV {args.iperf_csv}",
                file=sys.stderr,
            )

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
