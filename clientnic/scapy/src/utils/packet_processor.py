"""PacketProcessor: SYN and SYN-ACK handling + spoofed SYN-ACK generation."""

import random
import logging

from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP
from scapy.sendrecv import send, sendp

from src.utils.flow_table import FlowKey, FlowTable

logger = logging.getLogger("clientnic")


class PacketProcessor:
    def __init__(self, flow_table: FlowTable, client_iface: str, server_iface: str):
        self._flow_table = flow_table
        self._client_iface = client_iface
        self._server_iface = server_iface

    # ── SYN from client ──────────────────────────────────────────────────────

    def process_syn(self, packet) -> None:
        key = FlowTable.extract_key(packet)
        if self._flow_table.get_flow(key) is not None:
            logger.debug("SYN retransmit ignored: %s", key)
            return
        spoofed_isn = self._generate_random_isn()
        self._flow_table.create_flow(key, packet[TCP].seq, spoofed_isn)
        syn_ack = self._create_syn_ack(packet, spoofed_isn)
        sendp(syn_ack, iface=self._client_iface, verbose=False)    # L2 — keep spoofed MACs
        send(packet[IP], iface=self._server_iface, verbose=False)  # L3 forward original SYN
        logger.info("SYN: flow created + spoofed SYN-ACK sent [%s]", key)

    # ── real SYN-ACK from server ─────────────────────────────────────────────

    def process_syn_ack(self, packet) -> None:
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
        buffered = self._flow_table.flush_buffer(reverse_key)
        for pkt in buffered:
            pkt2 = pkt[IP].copy()
            pkt2[TCP].ack = (pkt2[TCP].ack - delta) & 0xFFFFFFFF
            del pkt2[IP].chksum
            del pkt2[TCP].chksum
            send(pkt2, iface=self._server_iface, verbose=False)
        logger.info("SYN-ACK: delta=%d, flushed %d pkts [%s]", delta, len(buffered), reverse_key)
        # real SYN-ACK dropped — client already has the spoofed one

    # ── SYN-ACK construction ─────────────────────────────────────────────────

    def _create_syn_ack(self, syn_packet, spoofed_isn: int):
        return (
            Ether(src=syn_packet[Ether].dst, dst=syn_packet[Ether].src)
            / IP(src=syn_packet[IP].dst, dst=syn_packet[IP].src)
            / TCP(
                sport=syn_packet[TCP].dport,
                dport=syn_packet[TCP].sport,
                seq=spoofed_isn,
                ack=(syn_packet[TCP].seq + 1) & 0xFFFFFFFF,
                flags="SA",
            )
        )

    @staticmethod
    def _generate_random_isn() -> int:
        return random.randint(0, 0xFFFFFFFF)
