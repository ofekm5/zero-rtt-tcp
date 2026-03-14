"""Dispatcher: Parse → Decide → route to correct pipeline stage."""

import logging

from scapy.layers.l2 import Ether, get_if_hwaddr
from scapy.layers.inet import IP, TCP

from src.utils.flow_table import FlowTable

logger = logging.getLogger("clientnic")


class Dispatcher:
    def __init__(self, syn_handler, syn_ack_handler, translator,
                 flow_table, client_iface: str, server_iface: str):
        self._syn = syn_handler
        self._syn_ack = syn_ack_handler
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

    def dispatch(self, packet) -> None:
        # --- Parse ---
        if not packet.haslayer(Ether) or not packet.haslayer(IP) or not packet.haslayer(TCP):
            return
        if packet[Ether].src.lower() in self._our_macs:
            return

        ingress = packet.sniffed_on
        flags = packet[TCP].flags
        is_syn = flags.S and not flags.A
        is_syn_ack = flags.S and flags.A

        # Skip outgoing frames re-captured on eth1
        if ingress == self._server_iface:
            if self._flow_table.get_flow(FlowTable.extract_key(packet)) is not None:
                return

        # --- Decide + route ---
        if ingress == self._client_iface:
            if is_syn:
                self._syn.process(packet)
            else:
                self._translator.translate_c2s(packet)
        elif ingress == self._server_iface:
            if is_syn_ack:
                self._syn_ack.process(packet)
            else:
                self._translator.translate_s2c(packet)
