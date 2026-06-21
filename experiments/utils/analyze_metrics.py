#!/usr/bin/env python3
"""
Offline pcap analyzer for 0-RTT endpoint metrics.

Computes three metrics from endpoint packet captures:
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
"""

import argparse
import csv
import sys
from typing import Optional, Tuple

try:
    from scapy.all import rdpcap, IP, TCP
except ImportError:
    print("ERROR: scapy not found. Install with: pip3 install scapy", file=sys.stderr)
    sys.exit(2)


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def _flow_str(src_ip: str, src_port: int, dst_ip: str, dst_port: int) -> str:
    return f"{src_ip}:{src_port}-{dst_ip}:{dst_port}"


def _has_payload(pkt) -> bool:
    """True if TCP packet carries application payload (payload length > 0)."""
    if not pkt.haslayer(TCP):
        return False
    tcp = pkt[TCP]
    # Raw payload = everything after IP/TCP headers
    if not pkt.haslayer(IP):
        return False
    ip = pkt[IP]
    ip_total = ip.len
    ip_hdr_len = ip.ihl * 4
    tcp_hdr_len = tcp.dataofs * 4
    payload_len = ip_total - ip_hdr_len - tcp_hdr_len
    return payload_len > 0


def _is_syn(pkt) -> bool:
    return (pkt.haslayer(TCP) and pkt.haslayer(IP)
            and bool(pkt[TCP].flags.S) and not bool(pkt[TCP].flags.A))


def _is_syn_ack(pkt) -> bool:
    return (pkt.haslayer(TCP) and pkt.haslayer(IP)
            and bool(pkt[TCP].flags.S) and bool(pkt[TCP].flags.A))


def _is_fin(pkt) -> bool:
    return pkt.haslayer(TCP) and bool(pkt[TCP].flags.F)


# --------------------------------------------------------------------------- #
# Client-side analysis
# --------------------------------------------------------------------------- #

def _analyze_client_flow(pkts, syn_pkt) -> Tuple[str, list]:
    """Compute send_unlock and fct for a single client-side flow anchored on syn_pkt."""
    syn_src_ip = syn_pkt[IP].src
    syn_src_port = syn_pkt[TCP].sport
    syn_dst_ip = syn_pkt[IP].dst
    syn_dst_port = syn_pkt[TCP].dport
    flow = _flow_str(syn_src_ip, syn_src_port, syn_dst_ip, syn_dst_port)
    t_syn = float(syn_pkt.time)

    flow_pkts = []
    for pkt in pkts:
        if not (pkt.haslayer(IP) and pkt.haslayer(TCP)):
            continue
        ip = pkt[IP]
        tcp = pkt[TCP]
        c2s = (ip.src == syn_src_ip and tcp.sport == syn_src_port
               and ip.dst == syn_dst_ip and tcp.dport == syn_dst_port)
        s2c = (ip.src == syn_dst_ip and tcp.sport == syn_dst_port
               and ip.dst == syn_src_ip and tcp.dport == syn_src_port)
        if c2s or s2c:
            flow_pkts.append((pkt, c2s, s2c))

    results = []

    first_payload_pkt = None
    for pkt, c2s, _ in flow_pkts:
        if c2s and _has_payload(pkt):
            first_payload_pkt = pkt
            break

    if first_payload_pkt is None:
        results.append({"kind": "missing", "event": "first_outbound_payload", "flow": flow})
    else:
        send_unlock_ms = (float(first_payload_pkt.time) - t_syn) * 1000.0
        results.append({
            "kind": "metric",
            "name": "send_unlock",
            "value_ms": send_unlock_ms,
            "node": "client",
            "flow": flow,
        })

    last_data_pkt = None
    for pkt, c2s, s2c in flow_pkts:
        if _has_payload(pkt) or _is_fin(pkt):
            last_data_pkt = pkt

    if last_data_pkt is None:
        results.append({"kind": "missing", "event": "last_data_or_FIN", "flow": flow})
    else:
        fct_ms = (float(last_data_pkt.time) - t_syn) * 1000.0
        results.append({
            "kind": "metric",
            "name": "fct",
            "value_ms": fct_ms,
            "node": "client",
            "flow": flow,
        })

    return flow, results


def analyze_client(pkts) -> Tuple[Optional[str], list]:
    """
    Find all outbound TCP flows (one per unique SYN 4-tuple) and compute metrics for each.
    Returns (first_flow_str_or_None, flat_list_of_all_metric_and_error_dicts).
    """
    seen: set = set()
    syns = []
    for pkt in pkts:
        if _is_syn(pkt):
            key = (pkt[IP].src, pkt[TCP].sport, pkt[IP].dst, pkt[TCP].dport)
            if key not in seen:
                seen.add(key)
                syns.append(pkt)

    if not syns:
        return None, [{"kind": "missing", "event": "SYN", "flow": "unknown"}]

    if len(syns) > 1:
        print(f"# info: {len(syns)} client flows found; emitting metrics for all",
              file=sys.stderr)

    all_results: list = []
    first_flow: Optional[str] = None
    for syn in syns:
        flow, results = _analyze_client_flow(pkts, syn)
        if first_flow is None:
            first_flow = flow
        all_results.extend(results)

    return first_flow, all_results


# --------------------------------------------------------------------------- #
# Server-side analysis
# --------------------------------------------------------------------------- #

def _analyze_server_flow(pkts, syn_ack_pkt) -> Tuple[str, list]:
    """Compute server_gap for a single server-side flow anchored on syn_ack_pkt."""
    server_ip = syn_ack_pkt[IP].src
    server_port = syn_ack_pkt[TCP].sport
    client_ip = syn_ack_pkt[IP].dst
    client_port = syn_ack_pkt[TCP].dport
    flow = _flow_str(client_ip, client_port, server_ip, server_port)
    t_syn_ack = float(syn_ack_pkt.time)

    flow_pkts = []
    for pkt in pkts:
        if not (pkt.haslayer(IP) and pkt.haslayer(TCP)):
            continue
        ip = pkt[IP]
        tcp = pkt[TCP]
        c2s = (ip.src == client_ip and tcp.sport == client_port
               and ip.dst == server_ip and tcp.dport == server_port)
        s2c = (ip.src == server_ip and tcp.sport == server_port
               and ip.dst == client_ip and tcp.dport == client_port)
        if c2s or s2c:
            flow_pkts.append((pkt, c2s, s2c))

    results = []

    first_inbound_payload = None
    for pkt, c2s, _ in flow_pkts:
        if c2s and _has_payload(pkt) and float(pkt.time) >= t_syn_ack:
            first_inbound_payload = pkt
            break

    if first_inbound_payload is None:
        results.append({"kind": "missing", "event": "first_inbound_payload", "flow": flow})
    else:
        server_gap_ms = (float(first_inbound_payload.time) - t_syn_ack) * 1000.0
        results.append({
            "kind": "metric",
            "name": "server_gap",
            "value_ms": server_gap_ms,
            "node": "server",
            "flow": flow,
        })

    return flow, results


def analyze_server(pkts) -> Tuple[Optional[str], list]:
    """
    Find all server-side TCP flows (one per unique SYN-ACK 4-tuple) and compute
    server_gap for each. Returns (first_flow_str_or_None, flat_list_of_results).
    """
    seen: set = set()
    syn_acks = []
    for pkt in pkts:
        if _is_syn_ack(pkt):
            key = (pkt[IP].src, pkt[TCP].sport, pkt[IP].dst, pkt[TCP].dport)
            if key not in seen:
                seen.add(key)
                syn_acks.append(pkt)

    if not syn_acks:
        return None, [{"kind": "missing", "event": "SYN-ACK", "flow": "unknown"}]

    if len(syn_acks) > 1:
        print(f"# info: {len(syn_acks)} server flows found; emitting metrics for all",
              file=sys.stderr)

    all_results: list = []
    first_flow: Optional[str] = None
    for syn_ack in syn_acks:
        flow, results = _analyze_server_flow(pkts, syn_ack)
        if first_flow is None:
            first_flow = flow
        all_results.extend(results)

    return first_flow, all_results


# --------------------------------------------------------------------------- #
# iperf CSV cross-check
# --------------------------------------------------------------------------- #

def parse_iperf_csv_duration(csv_path: str) -> Optional[float]:
    """
    Parse an iperf2 -yC CSV file and return the reported transfer duration in ms.
    iperf2 CSV format (comma-separated):
      timestamp,src_ip,src_port,dst_ip,dst_port,transfer_id,interval,transfer,bandwidth
    The interval field is like "0.0-10.0" — duration = end - start.
    We find the 'SUM' row (transfer_id == -1) or the last data row for total duration.
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
        required=True,
        help="Client-host pcap file. Yields fct and send_unlock metrics.",
    )
    parser.add_argument(
        "--server-pcap",
        default=None,
        help="Server-host pcap file (optional). Yields server_gap metric.",
    )
    parser.add_argument(
        "--iperf-csv",
        default=None,
        help="iperf2 -yC CSV file (optional). Cross-checks pcap-derived FCT. "
             "Warns if divergence > 10 ms; pcap value remains authoritative.",
    )
    args = parser.parse_args()

    exit_code = 0

    # --- Client pcap ---
    try:
        client_pkts = rdpcap(args.client_pcap)
    except Exception as exc:
        print(f"ERROR: cannot read {args.client_pcap}: {exc}", file=sys.stderr)
        return 1

    if len(client_pkts) == 0:
        print(f"missing=empty_capture flow=unknown", flush=True)
        return 1

    _flow, client_results = analyze_client(client_pkts)

    fct_ms: Optional[float] = None
    for result in client_results:
        emit(result)
        if result["kind"] == "missing":
            exit_code = 1
        elif result["kind"] == "metric" and result["name"] == "fct":
            fct_ms = result["value_ms"]

    # --- Server pcap (optional) ---
    if args.server_pcap is not None:
        try:
            server_pkts = rdpcap(args.server_pcap)
        except Exception as exc:
            print(f"ERROR: cannot read {args.server_pcap}: {exc}", file=sys.stderr)
            return 1

        if len(server_pkts) == 0:
            print(f"missing=empty_server_capture flow=unknown", flush=True)
            exit_code = 1
        else:
            _sflow, server_results = analyze_server(server_pkts)
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
