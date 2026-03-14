"""Unit tests for pipeline stages."""

import pytest
import threading
from unittest.mock import MagicMock, patch, ANY

from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP

from src.utils.buffer import PacketBuffer
from src.utils.flow_table import FlowKey, FlowTable
from src.pipeline.syn_handler import SynHandler
from src.pipeline.syn_ack_handler import SynAckHandler
from src.pipeline.translator import Translator
from src.pipeline.dispatcher import Dispatcher


# ---------------------------------------------------------------------------
# PacketBuffer
# ---------------------------------------------------------------------------

class TestPacketBuffer:
    """Tests for PacketBuffer class."""

    def test_add_single_packet(self):
        buffer = PacketBuffer()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        mock_packet = MagicMock()

        buffer.add(key, mock_packet)
        packets = buffer.flush(key)

        assert len(packets) == 1
        assert packets[0] is mock_packet

    def test_add_multiple_packets_same_flow(self):
        buffer = PacketBuffer()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        packets_in = [MagicMock() for _ in range(5)]

        for pkt in packets_in:
            buffer.add(key, pkt)

        packets_out = buffer.flush(key)

        assert len(packets_out) == 5
        assert packets_out == packets_in

    def test_flush_removes_packets(self):
        buffer = PacketBuffer()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        buffer.add(key, MagicMock())

        buffer.flush(key)
        packets = buffer.flush(key)

        assert packets == []

    def test_flush_nonexistent_key(self):
        buffer = PacketBuffer()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)

        packets = buffer.flush(key)

        assert packets == []

    def test_multiple_flows_isolated(self):
        buffer = PacketBuffer()
        key1 = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)
        key2 = FlowKey("1.1.1.1", 101, "2.2.2.2", 80)
        pkt1 = MagicMock()
        pkt2 = MagicMock()

        buffer.add(key1, pkt1)
        buffer.add(key2, pkt2)

        packets1 = buffer.flush(key1)
        packets2 = buffer.flush(key2)

        assert packets1 == [pkt1]
        assert packets2 == [pkt2]

    def test_thread_safety(self):
        buffer = PacketBuffer()
        key = FlowKey("1.1.1.1", 100, "2.2.2.2", 80)

        def add_packets():
            for _ in range(100):
                buffer.add(key, MagicMock())

        threads = [threading.Thread(target=add_packets) for _ in range(3)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        packets = buffer.flush(key)
        assert len(packets) == 300


# ---------------------------------------------------------------------------
# SynHandler
# ---------------------------------------------------------------------------

class TestSynHandler:
    """Tests for SynHandler."""

    @pytest.fixture
    def setup(self):
        flow_table = FlowTable()
        spoofer = MagicMock()
        spoofer.generate_random_isn.return_value = 5000
        spoofer.create_syn_ack.return_value = MagicMock()
        return flow_table, spoofer

    def _make_syn(self):
        return (
            Ether(src="aa:bb:cc:dd:ee:01", dst="aa:bb:cc:dd:ee:02")
            / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=80, seq=1000, flags="S")
        )

    def test_syn_creates_flow(self, setup):
        flow_table, spoofer = setup
        with patch("src.pipeline.syn_handler.tx") as mock_tx:
            stage = SynHandler(flow_table, spoofer, "eth0", "eth1")
            stage.process(self._make_syn())

        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        entry = flow_table.get_flow(key)
        assert entry is not None
        assert entry.client_isn == 1000
        assert entry.spoofed_server_isn == 5000

    def test_syn_sends_spoofed_syn_ack_via_sendp(self, setup):
        flow_table, spoofer = setup
        with patch("src.pipeline.syn_handler.tx") as mock_tx:
            stage = SynHandler(flow_table, spoofer, "eth0", "eth1")
            stage.process(self._make_syn())

        mock_tx.send_spoofed.assert_called_once_with(ANY, "eth0")

    def test_syn_forwards_original_via_send(self, setup):
        flow_table, spoofer = setup
        with patch("src.pipeline.syn_handler.tx") as mock_tx:
            stage = SynHandler(flow_table, spoofer, "eth0", "eth1")
            stage.process(self._make_syn())

        mock_tx.forward.assert_called_once_with(ANY, "eth1")

    def test_syn_retransmit_ignored(self, setup):
        flow_table, spoofer = setup
        spoofer.generate_random_isn.side_effect = [1000, 2000]
        with patch("src.pipeline.syn_handler.tx"):
            stage = SynHandler(flow_table, spoofer, "eth0", "eth1")
            stage.process(self._make_syn())
            stage.process(self._make_syn())  # retransmit

        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        # First ISN kept — retransmit ignored
        assert flow_table.get_flow(key).spoofed_server_isn == 1000


# ---------------------------------------------------------------------------
# SynAckHandler
# ---------------------------------------------------------------------------

class TestSynAckHandler:
    """Tests for SynAckHandler."""

    def test_syn_ack_sets_delta_and_flushes_buffer(self):
        flow_table = FlowTable()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        flow_table.create_flow(key, client_isn=1000, spoofed_isn=5000)

        buffer = PacketBuffer()
        buffered_pkt = (
            Ether() / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=80, seq=1001, ack=5001, flags="A")
        )
        buffer.add(key, buffered_pkt)

        stage = SynAckHandler(flow_table, buffer, "eth1")
        syn_ack = (
            Ether() / IP(src="10.0.0.1", dst="192.168.1.1")
            / TCP(sport=80, dport=12345, seq=3000, ack=1001, flags="SA")
        )
        with patch("src.pipeline.syn_ack_handler.tx") as mock_tx:
            stage.process(syn_ack)

        entry = flow_table.get_flow(key)
        # delta = (5000 - 3000) & 0xFFFFFFFF = 2000
        assert entry.seq_delta == 2000
        # buffered packet should have been forwarded
        mock_tx.forward_rewritten.assert_called_once()

    def test_syn_ack_unknown_flow_logs_warning(self):
        flow_table = FlowTable()
        buffer = PacketBuffer()
        stage = SynAckHandler(flow_table, buffer, "eth1")

        syn_ack = (
            Ether() / IP(src="10.0.0.1", dst="192.168.1.1")
            / TCP(sport=80, dport=12345, seq=3000, ack=1001, flags="SA")
        )
        with patch("src.pipeline.syn_ack_handler.tx"):
            stage.process(syn_ack)  # should not raise


# ---------------------------------------------------------------------------
# Translator
# ---------------------------------------------------------------------------

class TestTranslator:
    """Tests for Translator."""

    def _c2s_packet(self):
        return (
            Ether() / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=80, seq=1001, ack=5001, flags="A")
        )

    def _s2c_packet(self):
        return (
            Ether() / IP(src="10.0.0.1", dst="192.168.1.1")
            / TCP(sport=80, dport=12345, seq=3001, ack=1001, flags="A")
        )

    def test_translate_c2s_buffers_when_no_delta(self):
        flow_table = FlowTable()
        buffer = PacketBuffer()
        flow_table.create_flow(
            FlowKey("192.168.1.1", 12345, "10.0.0.1", 80), 1000, 5000
        )
        # delta not yet set (still None)

        translator = Translator(flow_table, buffer, "eth0", "eth1")
        with patch("src.pipeline.translator.tx"):
            translator.translate_c2s(self._c2s_packet())

        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        assert len(buffer.flush(key)) == 1

    def test_translate_c2s_rewrites_ack_when_delta_known(self):
        flow_table = FlowTable()
        buffer = PacketBuffer()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        flow_table.create_flow(key, 1000, 5000)
        flow_table.set_delta(key, 3000)  # delta = 2000

        translator = Translator(flow_table, buffer, "eth0", "eth1")
        with patch("src.pipeline.translator.tx") as mock_tx:
            translator.translate_c2s(self._c2s_packet())

        mock_tx.forward_rewritten.assert_called_once()

    def test_translate_s2c_rewrites_seq(self):
        flow_table = FlowTable()
        buffer = PacketBuffer()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        flow_table.create_flow(key, 1000, 5000)
        flow_table.set_delta(key, 3000)  # delta = 2000

        translator = Translator(flow_table, buffer, "eth0", "eth1")
        with patch("src.pipeline.translator.tx") as mock_tx:
            translator.translate_s2c(self._s2c_packet())

        mock_tx.forward_rewritten.assert_called_once()

    def test_translate_s2c_drops_unknown_flow(self):
        flow_table = FlowTable()
        buffer = PacketBuffer()
        translator = Translator(flow_table, buffer, "eth0", "eth1")
        with patch("src.pipeline.translator.tx") as mock_tx:
            translator.translate_s2c(self._s2c_packet())

        mock_tx.forward_rewritten.assert_not_called()


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

class TestDispatcher:
    """Tests for Dispatcher."""

    def _make_dispatcher(self, client_iface="eth0", server_iface="eth1"):
        flow_table = FlowTable()
        syn_stage = MagicMock()
        syn_ack_stage = MagicMock()
        translator = MagicMock()
        with patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff"):
            dispatcher = Dispatcher(syn_stage, syn_ack_stage, translator,
                                    flow_table, client_iface, server_iface)
        return dispatcher, flow_table, syn_stage, syn_ack_stage, translator

    def _make_packet(self, iface, flags, src_mac="11:22:33:44:55:66"):
        pkt = (
            Ether(src=src_mac, dst="aa:bb:cc:dd:ee:ff")
            / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=8080, flags=flags)
        )
        pkt.sniffed_on = iface
        return pkt

    def test_non_tcp_ignored(self):
        dispatcher, *_ = self._make_dispatcher()
        pkt = Ether() / IP()
        pkt.sniffed_on = "eth0"
        dispatcher.dispatch(pkt)  # should not raise

    def test_our_mac_skipped(self):
        dispatcher, _, syn_stage, *_ = self._make_dispatcher()
        pkt = self._make_packet("eth0", "S", src_mac="aa:bb:cc:dd:ee:ff")
        dispatcher.dispatch(pkt)
        syn_stage.process.assert_not_called()

    def test_syn_from_client_routed_to_syn_stage(self):
        dispatcher, _, syn_stage, *_ = self._make_dispatcher()
        pkt = self._make_packet("eth0", "S")
        dispatcher.dispatch(pkt)
        syn_stage.process.assert_called_once_with(pkt)

    def test_syn_ack_from_server_routed_to_syn_ack_stage(self):
        dispatcher, _, _, syn_ack_stage, _ = self._make_dispatcher()
        pkt = self._make_packet("eth1", "SA")
        dispatcher.dispatch(pkt)
        syn_ack_stage.process.assert_called_once_with(pkt)

    def test_data_from_client_routed_to_translate_c2s(self):
        dispatcher, _, _, _, translator = self._make_dispatcher()
        pkt = self._make_packet("eth0", "PA")
        dispatcher.dispatch(pkt)
        translator.translate_c2s.assert_called_once_with(pkt)

    def test_data_from_server_routed_to_translate_s2c(self):
        dispatcher, _, _, _, translator = self._make_dispatcher()
        pkt = self._make_packet("eth1", "PA")
        dispatcher.dispatch(pkt)
        translator.translate_s2c.assert_called_once_with(pkt)
