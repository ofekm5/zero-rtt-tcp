"""Stage: real SYN-ACK from server — compute delta, flush buffer, drop."""

import logging

from scapy.layers.inet import IP, TCP

from src.utils import tx
from src.utils.flow_table import FlowKey, FlowTable

logger = logging.getLogger("clientnic")


class SynAckHandler:
    def __init__(self, flow_table, buffer, server_iface: str):
        self._flow_table = flow_table
        self._buffer = buffer
        self._server_iface = server_iface

    def process(self, packet) -> None:
        reverse_key = FlowKey(
            src_ip=packet[IP].dst,
            src_port=packet[TCP].dport,
            dst_ip=packet[IP].src,
            dst_port=packet[TCP].sport,
        )
        delta = self._flow_table.set_delta(reverse_key, packet[TCP].seq)
        if delta is None:
            logger.warning("Real SYN-ACK for unknown flow: %s", reverse_key)
            return
        buffered = self._buffer.flush(reverse_key)
        for pkt in buffered:
            pkt2 = pkt[IP].copy()
            pkt2[TCP].ack = (pkt2[TCP].ack - delta) & 0xFFFFFFFF
            del pkt2[IP].chksum
            del pkt2[TCP].chksum
            tx.forward_rewritten(pkt2, self._server_iface)
        logger.info("SYN-ACK: delta=%d, flushed %d pkts [%s]", delta, len(buffered), reverse_key)
        # real SYN-ACK dropped — client already received the spoofed one
