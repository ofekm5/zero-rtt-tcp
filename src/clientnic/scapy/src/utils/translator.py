"""Translator: handles seq/ack rewriting for both data directions."""

import logging

from scapy.layers.inet import IP, TCP
from scapy.sendrecv import send

from src.utils.flow_table import FlowKey, FlowTable

logger = logging.getLogger("clientnic")


class Translator:
    def __init__(self, flow_table: FlowTable, client_iface: str, server_iface: str):
        self._flow_table = flow_table
        self._client_iface = client_iface
        self._server_iface = server_iface

    def translate_c2s(self, packet) -> None:
        """Client→server: subtract delta from ACK, or buffer if delta unknown."""
        key = FlowTable.extract_key(packet)
        entry = self._flow_table.get_flow(key)
        if entry is not None and entry.seq_delta is not None:
            pkt = packet[IP].copy()
            pkt[TCP].ack = (pkt[TCP].ack - entry.seq_delta) & 0xFFFFFFFF
            del pkt[IP].chksum
            del pkt[TCP].chksum
            send(pkt, iface=self._server_iface, verbose=False)
        else:
            self._flow_table.buffer_packet(key, packet)

    def translate_s2c(self, packet) -> None:
        """Server→client: add delta to SEQ."""
        reverse_key = FlowKey(
            src_ip=packet[IP].dst,
            src_port=packet[TCP].dport,
            dst_ip=packet[IP].src,
            dst_port=packet[TCP].sport,
        )
        entry = self._flow_table.get_flow(reverse_key)
        if entry is None or entry.seq_delta is None:
            logger.warning("Data from server for unknown/unready flow: %s", reverse_key)
            return
        pkt = packet[IP].copy()
        pkt[TCP].seq = (pkt[TCP].seq + entry.seq_delta) & 0xFFFFFFFF
        del pkt[IP].chksum
        del pkt[TCP].chksum
        send(pkt, iface=self._client_iface, verbose=False)
