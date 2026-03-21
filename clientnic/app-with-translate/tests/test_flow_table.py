"""Unit tests for flow_table.py"""

import pytest
from unittest.mock import MagicMock
import threading

from src.utils.flow_table import FlowKey, FlowEntry, FlowTable


class TestFlowKey:
    """Tests for FlowKey dataclass."""

    def test_creation(self):
        key = FlowKey(
            src_ip="192.168.1.1",
            src_port=12345,
            dst_ip="10.0.0.1",
            dst_port=80
        )
        assert key.src_ip == "192.168.1.1"
        assert key.src_port == 12345
        assert key.dst_ip == "10.0.0.1"
        assert key.dst_port == 80

    def test_equality(self):
        key1 = FlowKey("1.1.1.1", 100, "2.2.2.2", 200)
        key2 = FlowKey("1.1.1.1", 100, "2.2.2.2", 200)
        key3 = FlowKey("1.1.1.1", 100, "2.2.2.2", 201)
        assert key1 == key2
        assert key1 != key3

    def test_hashable(self):
        key1 = FlowKey("1.1.1.1", 100, "2.2.2.2", 200)
        key2 = FlowKey("1.1.1.1", 100, "2.2.2.2", 200)
        d = {key1: "value"}
        assert d[key2] == "value"

    def test_immutable(self):
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 200)
        with pytest.raises(AttributeError):
            key.src_port = 999


class TestFlowEntry:
    """Tests for FlowEntry dataclass."""

    def test_creation_with_defaults(self):
        entry = FlowEntry(client_isn=1000, spoofed_server_isn=2000)
        assert entry.client_isn == 1000
        assert entry.spoofed_server_isn == 2000
        assert entry.state == "SYN_SENT"

    def test_creation_with_custom_state(self):
        entry = FlowEntry(client_isn=1000, spoofed_server_isn=2000, state="ESTABLISHED")
        assert entry.state == "ESTABLISHED"

    def test_mutable(self):
        entry = FlowEntry(client_isn=1000, spoofed_server_isn=2000)
        entry.state = "ESTABLISHED"
        assert entry.state == "ESTABLISHED"


class TestFlowTable:
    """Tests for FlowTable class."""

    def test_create_flow(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        entry = table.create_flow(key, client_isn=1000, spoofed_isn=2000)
        assert entry.client_isn == 1000
        assert entry.spoofed_server_isn == 2000
        assert entry.state == "SYN_SENT"

    def test_get_flow_exists(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        table.create_flow(key, 1000, 2000)
        entry = table.get_flow(key)
        assert entry is not None
        assert entry.client_isn == 1000

    def test_get_flow_not_exists(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        assert table.get_flow(key) is None

    def test_overwrite_flow(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        table.create_flow(key, 1000, 2000)
        table.create_flow(key, 3000, 4000)
        entry = table.get_flow(key)
        assert entry.client_isn == 3000
        assert entry.spoofed_server_isn == 4000

    def test_multiple_flows(self):
        table = FlowTable()
        key1 = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        key2 = FlowKey("1.1.1.1", 101, "2.2.2.2", 80)
        table.create_flow(key1, 1000, 2000)
        table.create_flow(key2, 3000, 4000)
        assert table.get_flow(key1).client_isn == 1000
        assert table.get_flow(key2).client_isn == 3000

    def test_extract_key(self):
        mock_packet = MagicMock()
        mock_ip = MagicMock()
        mock_tcp = MagicMock()
        mock_ip.src = "192.168.1.100"
        mock_ip.dst = "10.0.0.50"
        mock_tcp.sport = 54321
        mock_tcp.dport = 8080
        from scapy.layers.inet import IP, TCP
        mock_packet.__getitem__.side_effect = lambda layer: mock_ip if layer == IP else mock_tcp
        key = FlowTable.extract_key(mock_packet)
        assert key.src_ip == "192.168.1.100"
        assert key.src_port == 54321
        assert key.dst_ip == "10.0.0.50"
        assert key.dst_port == 8080

    def test_thread_safety(self):
        table = FlowTable()
        results = []

        def create_flows(start_port):
            for i in range(100):
                key = FlowKey("1.1.1.1", start_port + i, "2.2.2.2", 80)
                table.create_flow(key, i, i * 2)
                results.append(table.get_flow(key) is not None)

        threads = [
            threading.Thread(target=create_flows, args=(1000,)),
            threading.Thread(target=create_flows, args=(2000,)),
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert all(results)
        assert len(results) == 200


class TestFlowTableBuffer:
    """Tests for buffer_packet / flush_buffer on FlowTable."""

    def test_add_single_packet(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        pkt = MagicMock()
        table.buffer_packet(key, pkt)
        packets = table.flush_buffer(key)
        assert packets == [pkt]

    def test_add_multiple_packets_same_flow(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        pkts = [MagicMock() for _ in range(5)]
        for p in pkts:
            table.buffer_packet(key, p)
        assert table.flush_buffer(key) == pkts

    def test_flush_clears_buffer(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        table.buffer_packet(key, MagicMock())
        table.flush_buffer(key)
        assert table.flush_buffer(key) == []

    def test_flush_nonexistent_key(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        assert table.flush_buffer(key) == []

    def test_multiple_flows_isolated(self):
        table = FlowTable()
        key1 = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        key2 = FlowKey("1.1.1.1", 101, "2.2.2.2", 80)
        pkt1, pkt2 = MagicMock(), MagicMock()
        table.buffer_packet(key1, pkt1)
        table.buffer_packet(key2, pkt2)
        assert table.flush_buffer(key1) == [pkt1]
        assert table.flush_buffer(key2) == [pkt2]

    def test_thread_safety(self):
        table = FlowTable()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)

        def add_packets():
            for _ in range(100):
                table.buffer_packet(key, MagicMock())

        threads = [threading.Thread(target=add_packets) for _ in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert len(table.flush_buffer(key)) == 300
