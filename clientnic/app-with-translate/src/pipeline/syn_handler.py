"""Stage: SYN from client — create flow, send spoofed SYN-ACK (sendp L2), forward SYN."""

import logging

from src.utils import tx
from src.utils.flow_table import FlowTable
from scapy.layers.inet import TCP

logger = logging.getLogger("clientnic")


class SynHandler:
    def __init__(self, flow_table, spoofer, client_iface: str, server_iface: str):
        self._flow_table = flow_table
        self._spoofer = spoofer
        self._client_iface = client_iface
        self._server_iface = server_iface

    def process(self, packet) -> None:
        key = FlowTable.extract_key(packet)
        if self._flow_table.get_flow(key) is not None:
            logger.debug("SYN retransmit ignored: %s", key)
            return
        spoofed_isn = self._spoofer.generate_random_isn()
        self._flow_table.create_flow(key, packet[TCP].seq, spoofed_isn)
        syn_ack = self._spoofer.create_syn_ack(packet, spoofed_isn)
        tx.send_spoofed(syn_ack, self._client_iface)   # sendp — L2
        tx.forward(packet, self._server_iface)          # send — L3
        logger.info("SYN: flow created + spoofed SYN-ACK sent [%s]", key)
