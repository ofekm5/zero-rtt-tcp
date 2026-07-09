"""Unit tests for PacketProcessor (SYN/SYN-ACK handling + spoofed SYN-ACK construction)."""

import pytest
from unittest.mock import MagicMock, patch, ANY

from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP

from src.utils.flow_table import FlowKey, FlowTable
from src.utils.packet_processor import PacketProcessor


def _make_processor(flow_table=None):
    return PacketProcessor(flow_table or FlowTable(), "eth0", "eth1")


def _make_syn(seq=1000):
    return (
        Ether(src="aa:bb:cc:dd:ee:01", dst="aa:bb:cc:dd:ee:02")
        / IP(src="192.168.1.1", dst="10.0.0.1")
        / TCP(sport=12345, dport=80, seq=seq, flags="S")
    )


# ---------------------------------------------------------------------------
# _create_syn_ack
# ---------------------------------------------------------------------------

class TestCreateSynAck:

    def test_swaps_ether_addresses(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(), spoofed_isn=5000)
        assert syn_ack[Ether].src == "aa:bb:cc:dd:ee:02"
        assert syn_ack[Ether].dst == "aa:bb:cc:dd:ee:01"

    def test_swaps_ip_addresses(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(), spoofed_isn=5000)
        assert syn_ack[IP].src == "10.0.0.1"
        assert syn_ack[IP].dst == "192.168.1.1"

    def test_tcp_fields(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(), spoofed_isn=5000)
        assert syn_ack[TCP].sport == 80
        assert syn_ack[TCP].dport == 12345
        assert syn_ack[TCP].seq == 5000
        assert syn_ack[TCP].ack == 1001  # client_seq + 1
        assert syn_ack[TCP].flags == "SA"

    def test_flags_are_syn_ack(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(), spoofed_isn=0)
        assert syn_ack[TCP].flags.S == True
        assert syn_ack[TCP].flags.A == True
        assert syn_ack[TCP].flags.F == False
        assert syn_ack[TCP].flags.R == False

    def test_ack_wraparound(self):
        syn = (
            Ether(src="aa:bb:cc:dd:ee:01", dst="aa:bb:cc:dd:ee:02")
            / IP(src="1.1.1.1", dst="2.2.2.2")
            / TCP(sport=1000, dport=80, seq=0xFFFFFFFF, flags="S")
        )
        syn_ack = _make_processor()._create_syn_ack(syn, spoofed_isn=100)
        assert syn_ack[TCP].ack == 0

    def test_zero_seq(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(seq=0), spoofed_isn=0)
        assert syn_ack[TCP].ack == 1

    def test_max_isn(self):
        syn_ack = _make_processor()._create_syn_ack(_make_syn(), spoofed_isn=0xFFFFFFFF)
        assert syn_ack[TCP].seq == 0xFFFFFFFF


# ---------------------------------------------------------------------------
# _generate_random_isn
# ---------------------------------------------------------------------------

class TestGenerateRandomIsn:

    def test_within_32bit_range(self):
        for _ in range(100):
            isn = PacketProcessor._generate_random_isn()
            assert 0 <= isn <= 0xFFFFFFFF

    def test_produces_varied_values(self):
        isns = [PacketProcessor._generate_random_isn() for _ in range(10)]
        assert len(set(isns)) > 1

    @patch("src.utils.packet_processor.random.randint")
    def test_uses_full_range(self, mock_randint):
        mock_randint.return_value = 12345
        assert PacketProcessor._generate_random_isn() == 12345
        mock_randint.assert_called_once_with(0, 0xFFFFFFFF)


# ---------------------------------------------------------------------------
# process_syn
# ---------------------------------------------------------------------------

class TestProcessSyn:

    def test_creates_flow(self):
        ft = FlowTable()
        proc = _make_processor(ft)
        with patch("src.utils.packet_processor.sendp"), \
             patch("src.utils.packet_processor.send"), \
             patch.object(proc, "_generate_random_isn", return_value=5000):
            proc.process_syn(_make_syn())
        entry = ft.get_flow(FlowKey("192.168.1.1", 12345, "10.0.0.1", 80))
        assert entry is not None
        assert entry.client_isn == 1000
        assert entry.spoofed_server_isn == 5000

    def test_sends_spoofed_syn_ack_via_sendp(self):
        proc = _make_processor()
        with patch("src.utils.packet_processor.sendp") as mock_sendp, \
             patch("src.utils.packet_processor.send"):
            proc.process_syn(_make_syn())
        mock_sendp.assert_called_once_with(ANY, iface="eth0", verbose=False)

    def test_forwards_syn_via_send(self):
        proc = _make_processor()
        with patch("src.utils.packet_processor.sendp"), \
             patch("src.utils.packet_processor.send") as mock_send:
            proc.process_syn(_make_syn())
        mock_send.assert_called_once_with(ANY, iface="eth1", verbose=False)

    def test_retransmit_ignored(self):
        ft = FlowTable()
        proc = _make_processor(ft)
        isn_values = iter([1000, 2000])
        with patch("src.utils.packet_processor.sendp"), \
             patch("src.utils.packet_processor.send"), \
             patch.object(proc, "_generate_random_isn", side_effect=isn_values):
            proc.process_syn(_make_syn())
            proc.process_syn(_make_syn())  # retransmit
        assert ft.get_flow(FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)).spoofed_server_isn == 1000


# ---------------------------------------------------------------------------
# process_syn_ack
# ---------------------------------------------------------------------------

class TestProcessSynAck:

    def _make_syn_ack(self, server_seq=3000):
        return (
            Ether() / IP(src="10.0.0.1", dst="192.168.1.1")
            / TCP(sport=80, dport=12345, seq=server_seq, ack=1001, flags="SA")
        )

    def test_sets_delta(self):
        ft = FlowTable()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        ft.create_flow(key, client_isn=1000, spoofed_isn=5000)
        proc = PacketProcessor(ft, "eth0", "eth1")
        with patch("src.utils.packet_processor.send"), \
             patch("src.utils.packet_processor.sendp"):
            proc.process_syn_ack(self._make_syn_ack(server_seq=3000))
        assert ft.get_flow(key).seq_delta == 2000  # (5000 - 3000) & 0xFFFFFFFF

    def test_flushes_buffered_packets(self):
        ft = FlowTable()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        ft.create_flow(key, client_isn=1000, spoofed_isn=5000)
        buffered = (
            Ether() / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=80, seq=1001, ack=5001, flags="A")
        )
        ft.buffer_packet(key, buffered)
        proc = PacketProcessor(ft, "eth0", "eth1")
        with patch("src.utils.packet_processor.send") as mock_send, \
             patch("src.utils.packet_processor.sendp"):
            proc.process_syn_ack(self._make_syn_ack())
        mock_send.assert_called_once()  # buffered packet forwarded

    def test_unknown_flow_does_not_raise(self):
        proc = PacketProcessor(FlowTable(), "eth0", "eth1")
        with patch("src.utils.packet_processor.send"), \
             patch("src.utils.packet_processor.sendp"):
            proc.process_syn_ack(self._make_syn_ack())  # should not raise
