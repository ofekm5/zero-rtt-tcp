"""Packet transmission helpers — wraps Scapy send/sendp."""

from scapy.layers.inet import IP
from scapy.sendrecv import send, sendp


def send_spoofed(packet, iface: str) -> None:
    """Send crafted packet with Ether layer (L2) — preserves spoofed src/dst MACs."""
    sendp(packet, iface=iface, verbose=False)


def forward(packet, iface: str) -> None:
    """Forward packet via L3 — kernel handles L2 headers via routing/ARP."""
    send(packet[IP], iface=iface, verbose=False)


def forward_rewritten(packet, iface: str) -> None:
    """Forward already-modified IP/TCP packet (checksums pre-deleted)."""
    send(packet, iface=iface, verbose=False)
