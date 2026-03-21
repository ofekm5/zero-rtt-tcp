"""Pipeline: Parse → Decide → Forward — stateless packet forwarder."""
import logging
from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP
from scapy.sendrecv import send

logger = logging.getLogger("servernic")


def _tcp_flags(tcp) -> str:
    parts = []
    if tcp.flags.S: parts.append("SYN")
    if tcp.flags.A: parts.append("ACK")
    if tcp.flags.P: parts.append("PSH")
    if tcp.flags.F: parts.append("FIN")
    if tcp.flags.R: parts.append("RST")
    return "-".join(parts) if parts else "NONE"


class Pipeline:
    def __init__(self, client_iface: str = "eth1", server_iface: str = "eth2"):
        self.client_iface = client_iface
        self.server_iface = server_iface
        self._our_macs = set()
        for iface in (client_iface, server_iface):
            try:
                self._our_macs.add(get_if_hwaddr(iface).lower())
            except Exception:
                pass

    def feed(self, packet) -> None:
        metadata = self._parse(packet)
        if metadata is None:
            return
        self._decide_and_modify(metadata, packet)

    def _parse(self, packet):
        """Return (egress, direction) or None to drop."""
        if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
            return None
        if packet[Ether].src.lower() in self._our_macs:
            return None  # self-sent — prevents re-capture loop
        ingress = packet.sniffed_on
        if ingress == self.client_iface:
            return self.server_iface, "ClientNIC -> Server"
        elif ingress == self.server_iface:
            return self.client_iface, "Server -> ClientNIC"
        return None

    def _decide_and_modify(self, metadata, packet) -> None:
        egress, direction = metadata
        ip  = packet[IP]
        tcp = packet[TCP]
        logger.info("%s  %s:%s -> %s:%s [%s]",
                    direction, ip.src, tcp.sport, ip.dst, tcp.dport, _tcp_flags(tcp))
        send(packet[IP], iface=egress, verbose=False)
