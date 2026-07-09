"""Unit tests for Translator and Pipeline."""

import pytest
from unittest.mock import MagicMock, patch

from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP

from src.utils.flow_table import FlowKey, FlowTable
from src.utils.translator import Translator
from src.pipeline import Pipeline


# ---------------------------------------------------------------------------
# Translator
# ---------------------------------------------------------------------------

class TestTranslator:

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
        ft = FlowTable()
        ft.create_flow(FlowKey("192.168.1.1", 12345, "10.0.0.1", 80), 1000, 5000)
        translator = Translator(ft, "eth0", "eth1")
        with patch("src.utils.translator.send"):
            translator.translate_c2s(self._c2s_packet())
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        assert len(ft.flush_buffer(key)) == 1

    def test_translate_c2s_rewrites_ack_when_delta_known(self):
        ft = FlowTable()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        ft.create_flow(key, 1000, 5000)
        ft.set_delta(key, 3000)  # delta = 2000
        translator = Translator(ft, "eth0", "eth1")
        with patch("src.utils.translator.send") as mock_send:
            translator.translate_c2s(self._c2s_packet())
        mock_send.assert_called_once()

    def test_translate_s2c_rewrites_seq(self):
        ft = FlowTable()
        key = FlowKey("192.168.1.1", 12345, "10.0.0.1", 80)
        ft.create_flow(key, 1000, 5000)
        ft.set_delta(key, 3000)  # delta = 2000
        translator = Translator(ft, "eth0", "eth1")
        with patch("src.utils.translator.send") as mock_send:
            translator.translate_s2c(self._s2c_packet())
        mock_send.assert_called_once()

    def test_translate_s2c_drops_unknown_flow(self):
        translator = Translator(FlowTable(), "eth0", "eth1")
        with patch("src.utils.translator.send") as mock_send:
            translator.translate_s2c(self._s2c_packet())
        mock_send.assert_not_called()


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------

class TestPipeline:

    def _make_pipeline(self, client_iface="eth0", server_iface="eth1"):
        ft = FlowTable()
        processor = MagicMock()
        translator = MagicMock()
        with patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff"):
            pipeline = Pipeline(processor, translator, ft, client_iface, server_iface)
        return pipeline, ft, processor, translator

    def _make_packet(self, iface, flags, src_mac="11:22:33:44:55:66"):
        pkt = (
            Ether(src=src_mac, dst="aa:bb:cc:dd:ee:ff")
            / IP(src="192.168.1.1", dst="10.0.0.1")
            / TCP(sport=12345, dport=8080, flags=flags)
        )
        pkt.sniffed_on = iface
        return pkt

    def test_non_tcp_ignored(self):
        pipeline, *_ = self._make_pipeline()
        pkt = Ether() / IP()
        pkt.sniffed_on = "eth0"
        pipeline.feed(pkt)  # should not raise

    def test_our_mac_skipped(self):
        pipeline, _, processor, _ = self._make_pipeline()
        pkt = self._make_packet("eth0", "S", src_mac="aa:bb:cc:dd:ee:ff")
        pipeline.feed(pkt)
        processor.process_syn.assert_not_called()

    def test_syn_from_client_routed_to_process_syn(self):
        pipeline, _, processor, _ = self._make_pipeline()
        pkt = self._make_packet("eth0", "S")
        pipeline.feed(pkt)
        processor.process_syn.assert_called_once_with(pkt)

    def test_syn_ack_from_server_routed_to_process_syn_ack(self):
        pipeline, _, processor, _ = self._make_pipeline()
        pkt = self._make_packet("eth1", "SA")
        pipeline.feed(pkt)
        processor.process_syn_ack.assert_called_once_with(pkt)

    def test_data_from_client_routed_to_translate_c2s(self):
        pipeline, _, _, translator = self._make_pipeline()
        pkt = self._make_packet("eth0", "PA")
        pipeline.feed(pkt)
        translator.translate_c2s.assert_called_once_with(pkt)

    def test_data_from_server_routed_to_translate_s2c(self):
        pipeline, _, _, translator = self._make_pipeline()
        pkt = self._make_packet("eth1", "PA")
        pipeline.feed(pkt)
        translator.translate_s2c.assert_called_once_with(pkt)
