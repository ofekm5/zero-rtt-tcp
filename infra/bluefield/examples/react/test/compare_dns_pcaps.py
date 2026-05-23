
#!/usr/bin/env python3

"""
=== Script Name ===
compare_dns_pcaps.py

=== Description ===
This script compares two PCAP files containing DNS response traffic:
one captured on the **server side** (before processing) and the other on the **client side** (after processing).

It identifies DNS responses that:
- Were seen in the server capture but not observed on the client side (**False Positives**)
- Were seen in the client capture but do not match any server-side response (**False Negatives**)

Packet matching is based on the tuple:
    (UDP destination port, DNS transaction ID)

The script optionally prints the full list of mismatched packet keys when run with `-v` / `--verbose`.

=== Usage ===
python compare_dns_pcaps.py server.pcap client.pcap [-v]

Arguments:
- `server.pcap`: PCAP file containing server-side DNS responses
- `client.pcap`: PCAP file containing client-side DNS responses
- `-v`, `--verbose`: (optional) Print detailed lists of unmatched keys

=== Output ===
- Number of false positives and false negatives
- Detailed lists of unmatched keys if `-v` is provided

=== Example ===
python compare_dns_pcaps.py before_filter.pcap after_filter.pcap --verbose

=== Dependencies ===
- scapy (`pip install scapy`)

=== Notes ===
- Only DNS-over-UDP packets are considered
- Designed for validating filtering behavior, response delivery, or packet loss in DNS systems
"""
import argparse
from scapy.all import RawPcapReader, DNS, UDP, IP, Ether

def extract_dns_key(pkt):
    """Extract (dport, dns.id) tuple from DNS response packet"""
    if pkt.haslayer(DNS) and pkt.haslayer(UDP):
        udp = pkt[UDP]
        dns = pkt[DNS]
        return (udp.dport, dns.id)
    return None

def load_dns_keys(pcap_file):
    """Load DNS keys from the server-side PCAP"""
    server_keys = {}
    for pkt_data, meta in RawPcapReader(pcap_file):
        pkt = Ether(pkt_data)
        key = extract_dns_key(pkt)
        if key:
            timestamp = meta.sec + meta.usec / 1_000_000  # convert to seconds
            server_keys[key] = timestamp
    return server_keys

def stream_dns(pcap_file, server_keys):
    """Stream client-side PCAP and compare with server"""
    seen_keys = set()
    non_reqs = set()
    counter = 0
    for pkt_data, meta in RawPcapReader(pcap_file):
        counter += 1
        if counter % 10000 == 0:
            print(f"Processed {counter} packets")

        pkt = Ether(pkt_data)
        key = extract_dns_key(pkt)
        if key:
            if key in server_keys:
                seen_keys.add(key)
            else:
                non_reqs.add(key)
    return seen_keys, non_reqs

def main():
    parser = argparse.ArgumentParser(description="Compare DNS responses between two PCAPs.")
    parser.add_argument("server_pcap", help="Server-side PCAP file")
    parser.add_argument("client_pcap", help="Client-side PCAP file")
    parser.add_argument("-v", "--verbose", action="store_true", help="Print detailed key mismatches")
    args = parser.parse_args()

    print("[*] Loading server-side DNS responses...")
    server_keys = load_dns_keys(args.server_pcap)

    print("[*] Streaming client-side DNS responses...")
    seen_keys, non_reqs = stream_dns(args.client_pcap, server_keys)

    only_in_1 = set(server_keys.keys()) - seen_keys

    print("\n--- DNS Comparison Report ---")
    print(f"False Positives (seen in server, missing at client): {len(only_in_1)}")
    print(f"False Negatives (seen in client, missing in server): {len(non_reqs)}")

    if args.verbose:
        print("\nVerbose output enabled:")
        print("Exact packets in false positives:")
        print(only_in_1)
        print("Exact packets in false negatives:")
        print(non_reqs)

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print("Usage: python compare_dns_pcaps.py from_server.pcap after_react.pcap")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
