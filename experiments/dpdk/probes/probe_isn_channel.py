#!/usr/bin/env python3
"""Probe verification for the ISN ack-num channel (design D8).

Sends a SYN with ack_seq=0xDEADBEEF on the specified interface toward the
Server, then exits.  The ServerNIC-side capture (tcpdump or --server-pcap)
must show bytes 8-11 of that SYN unchanged (== 0xDEADBEEF) to confirm that
the AWS VPC path does not normalize the ack-num field on a SYN packet.

Run this on the ClientNIC VM with eth1 bound to the kernel (not DPDK) so that
Scapy can send via AF_PACKET:

    sudo python3 probe_isn_channel.py \
        --iface eth1 \
        --src-ip 10.0.1.10 --dst-ip 10.0.3.10 \
        --src-port 54321 --dst-port 8080

Then on the ServerNIC VM capture ingress on its ClientNIC-facing interface:
    sudo tcpdump -i eth1 -w /tmp/probe.pcap 'tcp and port 8080'

Verify with:
    python3 probe_verify.py /tmp/probe.pcap
"""

import argparse
import sys


def parse_args():
    p = argparse.ArgumentParser(description="ISN ack-num channel probe")
    p.add_argument("--iface",    required=True, help="Sending interface (e.g. eth1)")
    p.add_argument("--src-ip",   required=True, help="Source IP (ClientNIC eth1 IP)")
    p.add_argument("--dst-ip",   required=True, help="Destination IP (Server IP)")
    p.add_argument("--src-port", type=int, default=54321, help="Source TCP port")
    p.add_argument("--dst-port", type=int, default=8080,  help="Destination TCP port")
    p.add_argument("--probe-val", default="0xDEADBEEF",
                   help="Ack-num value to embed (default: 0xDEADBEEF)")
    return p.parse_args()


def main():
    args = parse_args()
    probe_val = int(args.probe_val, 16) if args.probe_val.startswith("0x") \
        else int(args.probe_val)

    try:
        from scapy.all import Ether, IP, TCP, get_if_hwaddr, sendp, conf
        conf.verb = 0
    except ImportError:
        print("ERROR: scapy is required.  Install with: pip install scapy", file=sys.stderr)
        sys.exit(1)

    src_mac = get_if_hwaddr(args.iface)

    pkt = (
        Ether(src=src_mac) /
        IP(src=args.src_ip, dst=args.dst_ip, ttl=64) /
        TCP(
            sport=args.src_port,
            dport=args.dst_port,
            flags="S",          # SYN only, no ACK flag
            seq=0x12345678,
            ack=probe_val,      # ack-num carries 0xDEADBEEF
            window=65535,
        )
    )

    print(f"Sending probe SYN on {args.iface}:")
    print(f"  {args.src_ip}:{args.src_port} -> {args.dst_ip}:{args.dst_port}")
    print(f"  ack-num = 0x{probe_val:08X}")

    sendp(pkt, iface=args.iface, verbose=False)
    print("Done.  Capture the ServerNIC ingress and run probe_verify.py to confirm.")


if __name__ == "__main__":
    main()
