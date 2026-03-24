"""Pipeline: Parse → Decide+Modify — routes packets to correct handler."""

import logging

from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP

from src.utils.flow_table import FlowTable

logger = logging.getLogger("clientnic")


class Pipeline:
    def __init__(self, packet_processor, translator, flow_table: FlowTable,
                 client_iface: str, server_iface: str):
        self._processor = packet_processor
        self._translator = translator
        self._flow_table = flow_table
        self._client_iface = client_iface
        self._server_iface = server_iface
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
        """Return (ingress, is_syn, is_syn_ack) or None to drop."""
        if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
            return None
        if packet[Ether].src.lower() in self._our_macs:
            return None
        ingress = packet.sniffed_on
        flags = packet[TCP].flags
        is_syn = bool(flags.S and not flags.A)
        is_syn_ack = bool(flags.S and flags.A)
        # Skip outgoing frames re-captured on eth1
        if ingress == self._server_iface:
            if self._flow_table.get_flow(FlowTable.extract_key(packet)) is not None:
                return None
        return ingress, is_syn, is_syn_ack

    def _decide_and_modify(self, metadata, packet) -> None:
        ingress, is_syn, is_syn_ack = metadata
        if ingress == self._client_iface:
            if is_syn:
                self._processor.process_syn(packet)
            else:
                self._translator.translate_c2s(packet)
        elif ingress == self._server_iface:
            if is_syn_ack:
                self._processor.process_syn_ack(packet)
            else:
                self._translator.translate_s2c(packet)
