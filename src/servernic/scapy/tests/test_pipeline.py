"""Unit tests for Pipeline."""

from unittest.mock import patch, MagicMock

import pytest
from scapy.layers.inet import IP, TCP
from scapy.layers.l2 import Ether

from src.pipeline import Pipeline


def _make_packet(sniffed_on: str, has_tcp: bool = True):
    pkt = Ether() / IP(src="10.1.0.1", dst="10.1.2.1") / TCP(sport=12345, dport=8080, flags="S")
    if not has_tcp:
        pkt = Ether() / IP(src="10.1.0.1", dst="10.1.2.1")
    pkt.sniffed_on = sniffed_on
    return pkt


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_forwards_from_client_to_server(mock_hwaddr, mock_send):
    p = Pipeline(client_iface="eth1", server_iface="eth2")
    p.feed(_make_packet(sniffed_on="eth1"))
    mock_send.assert_called_once()
    _, kwargs = mock_send.call_args
    assert kwargs["iface"] == "eth2"


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_forwards_from_server_to_client(mock_hwaddr, mock_send):
    p = Pipeline(client_iface="eth1", server_iface="eth2")
    p.feed(_make_packet(sniffed_on="eth2"))
    mock_send.assert_called_once()
    _, kwargs = mock_send.call_args
    assert kwargs["iface"] == "eth1"


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_ignores_non_tcp(mock_hwaddr, mock_send):
    p = Pipeline()
    p.feed(_make_packet(sniffed_on="eth1", has_tcp=False))
    mock_send.assert_not_called()


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_ignores_unknown_interface(mock_hwaddr, mock_send):
    p = Pipeline(client_iface="eth1", server_iface="eth2")
    p.feed(_make_packet(sniffed_on="eth0"))
    mock_send.assert_not_called()


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_custom_interface_names(mock_hwaddr, mock_send):
    p = Pipeline(client_iface="ens5", server_iface="ens6")
    p.feed(_make_packet(sniffed_on="ens5"))
    mock_send.assert_called_once()
    _, kwargs = mock_send.call_args
    assert kwargs["iface"] == "ens6"


@patch("src.pipeline.send")
@patch("src.pipeline.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_ignores_self_sent_packet(mock_hwaddr, mock_send):
    p = Pipeline(client_iface="eth1", server_iface="eth2")
    pkt = _make_packet(sniffed_on="eth1")
    pkt[Ether].src = "aa:bb:cc:dd:ee:ff"  # our own MAC
    p.feed(pkt)
    mock_send.assert_not_called()
