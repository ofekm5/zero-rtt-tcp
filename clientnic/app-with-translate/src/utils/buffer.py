"""Thread-safe packet buffer for flows awaiting delta calculation."""

import threading
from typing import Dict, List

from scapy.packet import Packet

from .flow_table import FlowKey


class PacketBuffer:
    """Thread-safe buffer for packets awaiting delta calculation."""

    def __init__(self):
        self._buffers: Dict[FlowKey, List[Packet]] = {}
        self._lock = threading.Lock()

    def add(self, key: FlowKey, packet: Packet) -> None:
        """Add packet to buffer for given flow."""
        with self._lock:
            if key not in self._buffers:
                self._buffers[key] = []
            self._buffers[key].append(packet)

    def flush(self, key: FlowKey) -> List[Packet]:
        """Remove and return all buffered packets for given flow."""
        with self._lock:
            return self._buffers.pop(key, [])
