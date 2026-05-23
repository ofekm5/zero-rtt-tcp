#!/usr/bin/env python3
"""
SYN Punt Test Sender

This script sends test packets to verify the SYN punt application:
1. TCP SYN packets (should be punted to application and printed)
2. TCP non-SYN packets (should be fast-forwarded in hardware)
3. Non-TCP packets (should be fast-forwarded)

Usage:
    sudo python3 test_sender.py <interface> [options]

Example:
    sudo python3 test_sender.py eth0 --syn-count 10 --data-count 100
"""

import argparse
import sys
import time

try:
    from scapy.all import *
except ImportError:
    print("Error: scapy not installed. Install with: pip3 install scapy")
    sys.exit(1)


def send_syn_packets(iface, dst_ip, dst_port, count=10, interval=0.1):
    """Send TCP SYN packets"""
    print(f"\n[*] Sending {count} TCP SYN packets to {dst_ip}:{dst_port}")

    for i in range(count):
        pkt = Ether()/IP(dst=dst_ip)/TCP(dport=dst_port, flags='S', seq=1000+i)
        sendp(pkt, iface=iface, verbose=False)
        print(f"    Sent SYN packet #{i+1} (seq={1000+i})")
        time.sleep(interval)

    print(f"[✓] Sent {count} SYN packets")


def send_syn_ack_packets(iface, dst_ip, dst_port, count=10, interval=0.1):
    """Send TCP SYN-ACK packets (should be fast-forwarded)"""
    print(f"\n[*] Sending {count} TCP SYN-ACK packets to {dst_ip}:{dst_port}")

    for i in range(count):
        pkt = Ether()/IP(dst=dst_ip)/TCP(dport=dst_port, flags='SA', seq=2000+i, ack=1)
        sendp(pkt, iface=iface, verbose=False)
        time.sleep(interval)

    print(f"[✓] Sent {count} SYN-ACK packets (should be fast-forwarded)")


def send_data_packets(iface, dst_ip, dst_port, count=100, interval=0.01):
    """Send TCP data packets (should be fast-forwarded)"""
    print(f"\n[*] Sending {count} TCP data packets to {dst_ip}:{dst_port}")

    for i in range(count):
        pkt = Ether()/IP(dst=dst_ip)/TCP(dport=dst_port, flags='PA', seq=3000+i, ack=1)/Raw(load=f"Data packet {i}")
        sendp(pkt, iface=iface, verbose=False)

        if (i+1) % 20 == 0:
            print(f"    Sent {i+1}/{count} data packets...")
        time.sleep(interval)

    print(f"[✓] Sent {count} data packets (should be fast-forwarded)")


def send_udp_packets(iface, dst_ip, dst_port, count=50, interval=0.01):
    """Send UDP packets (should be fast-forwarded)"""
    print(f"\n[*] Sending {count} UDP packets to {dst_ip}:{dst_port}")

    for i in range(count):
        pkt = Ether()/IP(dst=dst_ip)/UDP(dport=dst_port)/Raw(load=f"UDP packet {i}")
        sendp(pkt, iface=iface, verbose=False)
        time.sleep(interval)

    print(f"[✓] Sent {count} UDP packets (should be fast-forwarded)")


def main():
    parser = argparse.ArgumentParser(
        description='Send test packets for SYN punt application',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Send default test suite
  sudo python3 test_sender.py eth0

  # Send only SYN packets
  sudo python3 test_sender.py eth0 --syn-only --syn-count 20

  # Send comprehensive test
  sudo python3 test_sender.py eth0 --syn-count 50 --data-count 500 --udp-count 100
        """
    )

    parser.add_argument('interface', help='Network interface to send packets on')
    parser.add_argument('--dst-ip', default='10.0.0.2', help='Destination IP address (default: 10.0.0.2)')
    parser.add_argument('--dst-port', type=int, default=80, help='Destination TCP/UDP port (default: 80)')

    parser.add_argument('--syn-count', type=int, default=10, help='Number of SYN packets to send (default: 10)')
    parser.add_argument('--syn-ack-count', type=int, default=10, help='Number of SYN-ACK packets (default: 10)')
    parser.add_argument('--data-count', type=int, default=100, help='Number of TCP data packets (default: 100)')
    parser.add_argument('--udp-count', type=int, default=50, help='Number of UDP packets (default: 50)')

    parser.add_argument('--syn-only', action='store_true', help='Send only SYN packets')
    parser.add_argument('--interval', type=float, default=0.1, help='Interval between packets in seconds (default: 0.1)')

    args = parser.parse_args()

    # Verify interface exists
    if args.interface not in get_if_list():
        print(f"Error: Interface '{args.interface}' not found")
        print(f"Available interfaces: {', '.join(get_if_list())}")
        return 1

    print("=" * 60)
    print("SYN Punt Application - Test Packet Sender")
    print("=" * 60)
    print(f"Interface: {args.interface}")
    print(f"Destination: {args.dst_ip}:{args.dst_port}")
    print("=" * 60)

    try:
        # Send SYN packets (should be punted to application)
        send_syn_packets(args.interface, args.dst_ip, args.dst_port,
                        args.syn_count, args.interval)

        if not args.syn_only:
            # Send SYN-ACK packets (should be fast-forwarded)
            send_syn_ack_packets(args.interface, args.dst_ip, args.dst_port,
                               args.syn_ack_count, args.interval)

            # Send TCP data packets (should be fast-forwarded)
            send_data_packets(args.interface, args.dst_ip, args.dst_port,
                            args.data_count, args.interval * 0.1)

            # Send UDP packets (should be fast-forwarded)
            send_udp_packets(args.interface, args.dst_ip, args.dst_port,
                           args.udp_count, args.interval * 0.1)

        print("\n" + "=" * 60)
        print("[✓] Test completed successfully!")
        print("=" * 60)
        print("\nExpected behavior:")
        print(f"  - {args.syn_count} SYN packets should appear in application output")
        if not args.syn_only:
            total_fast = args.syn_ack_count + args.data_count + args.udp_count
            print(f"  - {total_fast} packets should be fast-forwarded (not printed)")
        print("\nCheck the syn_punt application output to verify.")

        return 0

    except KeyboardInterrupt:
        print("\n\n[!] Interrupted by user")
        return 1
    except Exception as e:
        print(f"\n[!] Error: {e}")
        return 1


if __name__ == '__main__':
    if os.geteuid() != 0:
        print("Error: This script must be run as root (use sudo)")
        sys.exit(1)

    sys.exit(main())
