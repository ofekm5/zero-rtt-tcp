#!/usr/bin/env python3
"""Verify ISN ack-num channel probe capture.

Reads the pcap captured on ServerNIC ingress and confirms that the probe SYN
(with ack-num=0xDEADBEEF) arrived unchanged.  Prints PASS or FAIL with details.

Usage:
    python3 probe_verify.py /tmp/probe.pcap [--probe-val 0xDEADBEEF] [--src-port 54321]
"""

import argparse
import sys


def parse_args():
    p = argparse.ArgumentParser(description="ISN ack-num channel probe verifier")
    p.add_argument("pcap", help="Path to the pcap file from ServerNIC ingress capture")
    p.add_argument("--probe-val", default="0xDEADBEEF",
                   help="Expected ack-num value (default: 0xDEADBEEF)")
    p.add_argument("--src-port", type=int, default=54321,
                   help="Source TCP port used in probe (default: 54321)")
    return p.parse_args()


def main():
    args = parse_args()
    probe_val = int(args.probe_val, 16) if args.probe_val.startswith("0x") \
        else int(args.probe_val)

    try:
        from scapy.all import rdpcap, TCP, IP
    except ImportError:
        print("ERROR: scapy is required.  Install with: pip install scapy", file=sys.stderr)
        sys.exit(1)

    pkts = rdpcap(args.pcap)
    found = False
    for pkt in pkts:
        if not (pkt.haslayer(TCP) and pkt.haslayer(IP)):
            continue
        tcp = pkt[TCP]
        if tcp.sport != args.src_port:
            continue
        # SYN only (no ACK flag)
        if not (tcp.flags & 0x02) or (tcp.flags & 0x10):
            continue
        found = True
        actual = tcp.ack
        if actual == probe_val:
            print(f"PASS  ack-num=0x{actual:08X} -- field preserved end-to-end")
            sys.exit(0)
        else:
            print(f"FAIL  expected ack-num=0x{probe_val:08X}, got 0x{actual:08X}")
            print("      A middlebox normalized the ack-num field on this SYN.")
            print("      Fall back to a TCP-option channel.")
            sys.exit(1)

    if not found:
        print(f"FAIL  No probe SYN found in {args.pcap} (src_port={args.src_port})")
        sys.exit(1)


if __name__ == "__main__":
    main()
