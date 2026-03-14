"""RX: Parse → Decide → Forward — stateless packet dispatcher."""
import logging
from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP
from src.utils import tx

logger = logging.getLogger("servernic")


def _tcp_flags(tcp) -> str:
    parts = []
    if tcp.flags.S: parts.append("SYN")
    if tcp.flags.A: parts.append("ACK")
    if tcp.flags.P: parts.append("PSH")
    if tcp.flags.F: parts.append("FIN")
    if tcp.flags.R: parts.append("RST")
    return "-".join(parts) if parts else "NONE"


class Dispatcher:
    def __init__(self, client_iface: str = "eth1", server_iface: str = "eth2"):
        self.client_iface = client_iface
        self.server_iface = server_iface
        self._our_macs = set()
        for iface in (client_iface, server_iface):
            try:
                self._our_macs.add(get_if_hwaddr(iface).lower())
            except Exception:
                pass

    def dispatch(self, packet) -> None:
        # --- Parse ---
        if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
            return
        if packet[Ether].src.lower() in self._our_macs:
            return  # self-sent — prevents re-capture loop
        ingress = packet.sniffed_on
        ip  = packet[IP]
        tcp = packet[TCP]

        # --- Decide ---
        if ingress == self.client_iface:
            egress    = self.server_iface
            direction = "ClientNIC -> Server"
        elif ingress == self.server_iface:
            egress    = self.client_iface
            direction = "Server -> ClientNIC"
        else:
            return

        # --- Forward ---
        logger.info("%s  %s:%s -> %s:%s [%s]",
                    direction, ip.src, tcp.sport, ip.dst, tcp.dport, _tcp_flags(tcp))
        tx.forward(packet, egress)
