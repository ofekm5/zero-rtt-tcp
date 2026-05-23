"""
=== Script Name ===
generate_dns_queries.py

=== Description ===
This script generates a synthetic PCAP file containing 1,000,000 DNS query packets
sent over UDP from a fixed source IP to a destination DNS server.

Each packet includes:
- Random UDP source port (1024–65535)
- Random DNS transaction ID
- A single DNS query for a fixed domain (default: "www.example.com.")

Packet structure:
    Ether / IP / UDP / DNS / DNSQR

This is useful for:
- Load testing DNS filtering systems
- Benchmarking replay-based middlebox pipelines
- Generating input traffic for false positive/negative experiments

=== Usage ===
python generate_dns_queries.py output.pcap

Arguments:
- `output.pcap`: Path to write the generated PCAP file

=== Parameters (hardcoded in script) ===
- COUNT:    1,000,000 packets
- SRC_IP:   192.168.8.10
- DST_IP:   192.168.5.11
- DST_PORT: 53
- QNAME:    "www.example.com." (note the trailing dot)

=== Output ===
- A PCAP file containing 1M randomized DNS queries

=== Dependencies ===
- scapy (`pip install scapy`)

=== Notes ===
- `sync=True` ensures packets are flushed immediately to disk
- Packet contents are deterministic except for port and DNS ID
- Domain and IPs can be modified directly in the script
"""

import random
import sys
from scapy.all import Ether, IP, UDP, DNS, DNSQR, PcapWriter

COUNT    = 1_000_000
SRC_IP   = "192.168.8.10"
DST_IP   = "192.168.5.11"
DST_PORT = 53
QNAME    = "www.example.com."     # keep the trailing dot

def main(pcap_path: str) -> None:
    # Pre‑build the constant parts once
    eth_base = Ether(src="aa:bb:cc:dd:ee:ff", dst="ff:ee:dd:cc:bb:aa")
    ip_base  = IP(src=SRC_IP, dst=DST_IP)
    qd       = DNSQR(qname=QNAME)

    writer = PcapWriter(pcap_path, sync=True)   # auto‑detects link‑type
    try:
        for i in range(COUNT):
            sport = random.randint(1024, 65535)
            tid   = random.randint(0, 0xFFFF)

            pkt = (
                eth_base /
                ip_base /
                UDP(sport=sport, dport=DST_PORT) /
                DNS(id=tid, rd=1, qd=qd)
            )
            writer.write(pkt)

            if (i + 1) % 100_000 == 0:
                print(f"{i + 1:,} packets written…", flush=True)
    finally:
        writer.close()
        print(f"Done. PCAP saved to {pcap_path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"Usage: {sys.argv[0]} <output.pcap>")
    main(sys.argv[1])


