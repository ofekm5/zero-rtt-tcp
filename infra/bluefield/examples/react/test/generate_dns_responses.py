"""
=== Script Name ===
generate_dns_responses.py

=== Description ===
This script generates a synthetic PCAP file containing 1,000,000 DNS **response** packets
sent from a fixed DNS server IP to a client.

Each packet includes:
- Fixed source port 53 (standard DNS server port)
- Random destination port (mimicking different client queries)
- Random DNS transaction ID
- A DNS answer section with a fixed IP address (e.g., for "www.example.com.")

Packet structure:
    Ether / IP / UDP / DNS / DNSRR

=== Usage ===
python generate_dns_responses.py output.pcap

Arguments:
- `output.pcap`: Path to write the generated PCAP file

=== Parameters (hardcoded in script) ===
- COUNT:     1,000,000 packets
- SRC_IP:    192.168.5.15 (DNS server)
- DST_IP:    192.168.8.10 (Client)
- SRC_PORT:  53
- QNAME:     "www.example.com." (must include trailing dot)
- ANS_IP:    93.184.216.34 (IPv4 address in DNS answer)

=== Output ===
- A PCAP file simulating 1M DNS responses with randomized IDs and destination ports

=== Dependencies ===
- scapy (`pip install scapy`)

=== Notes ===
- `sync=True` flushes packets to disk immediately
- Useful for testing replay pipelines, false positives in filters, or latency experiments
- DNS `qd` section is technically malformed (uses DNSRR instead of DNSQR),
  but often tolerated by test tools — can be adjusted for realism
"""

import random
import sys
from scapy.all import Ether, IP, UDP, DNS, DNSRR, PcapWriter

COUNT    = 1_000_000
SRC_IP   = "192.168.5.15"
DST_IP   = "192.168.8.10"
SRC_PORT = 53
QNAME    = "www.example.com."     # trailing dot required
ANS_IP   = "93.184.216.34"        # example.com's IP

def main(pcap_path: str) -> None:
    eth_base = Ether(src="ff:ee:dd:cc:bb:aa", dst="aa:bb:cc:dd:ee:ff")
    ip_base  = IP(src=SRC_IP, dst=DST_IP)

    writer = PcapWriter(pcap_path, sync=True)
    try:
        for i in range(COUNT):
            dport = random.randint(1024, 65535)
            tid   = random.randint(0, 0xFFFF)

            dns_layer = DNS(
                id=tid,
                qr=1,        # This marks it as a response
                aa=1,        # Authoritative Answer flag (optional)
                rd=1,
                ra=1,
                qdcount=1,
                ancount=1,
                qd=DNSRR(rrname=QNAME, type='A'),
                an=DNSRR(rrname=QNAME, type='A', ttl=300, rdata=ANS_IP)
            )

            pkt = (
                eth_base /
                ip_base /
                UDP(sport=SRC_PORT, dport=dport) /
                dns_layer
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
