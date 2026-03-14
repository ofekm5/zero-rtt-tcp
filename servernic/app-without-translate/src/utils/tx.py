"""Transmission helpers for ServerNIC."""
from scapy.layers.inet import IP
from scapy.sendrecv import send


def forward(packet, iface: str) -> None:
    """Forward packet via L3 — kernel handles L2 headers via routing/ARP."""
    send(packet[IP], iface=iface, verbose=False)
