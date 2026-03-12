"""Stateless packet forwarder for ServerNIC."""

import logging

from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP
from scapy.sendrecv import send

logger = logging.getLogger("servernic")


class PacketForwarder:
    def __init__(self, client_iface: str = "eth1", server_iface: str = "eth2"):
        self.client_iface = client_iface
        self.server_iface = server_iface
        # Collect our own MAC addresses to filter out self-sent packets.
        # sniff() on AF_PACKET captures both incoming and outgoing frames;
        # without this check, send() output gets re-sniffed → infinite loop.
        self._our_macs = set()
        for iface in (client_iface, server_iface):
            try:
                self._our_macs.add(get_if_hwaddr(iface).lower())
            except Exception:
                pass

    def handle(self, packet) -> None:
        if not packet.haslayer(TCP):
            return

        # Skip packets we sent ourselves (prevents re-capture loop)
        if packet.haslayer(Ether) and packet[Ether].src.lower() in self._our_macs:
            return

        ingress = packet.sniffed_on

        if ingress == self.client_iface:
            egress = self.server_iface
            direction = "ClientNIC -> Server"
        elif ingress == self.server_iface:
            egress = self.client_iface
            direction = "Server -> ClientNIC"
        else:
            return

        ip = packet[IP]
        tcp = packet[TCP]
        flags = _tcp_flags(tcp)
        logger.info("%s  %s:%s -> %s:%s [%s]", direction, ip.src, tcp.sport, ip.dst, tcp.dport, flags)

        send(packet[IP], iface=egress, verbose=False)


def _tcp_flags(tcp) -> str:
    parts = []
    if tcp.flags.S:
        parts.append("SYN")
    if tcp.flags.A:
        parts.append("ACK")
    if tcp.flags.P:
        parts.append("PSH")
    if tcp.flags.F:
        parts.append("FIN")
    if tcp.flags.R:
        parts.append("RST")
    return "-".join(parts) if parts else "NONE"
