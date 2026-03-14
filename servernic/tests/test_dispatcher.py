"""Unit tests for Dispatcher."""

from unittest.mock import patch, MagicMock

import pytest
from scapy.layers.inet import IP, TCP
from scapy.layers.l2 import Ether

from src.pipeline.dispatcher import Dispatcher


def _make_packet(sniffed_on: str, has_tcp: bool = True):
    pkt = Ether() / IP(src="10.1.0.1", dst="10.1.2.1") / TCP(sport=12345, dport=8080, flags="S")
    if not has_tcp:
        pkt = Ether() / IP(src="10.1.0.1", dst="10.1.2.1")
    pkt.sniffed_on = sniffed_on
    return pkt


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_handle_forwards_from_client_to_server(mock_hwaddr, mock_forward):
    d = Dispatcher(client_iface="eth1", server_iface="eth2")
    pkt = _make_packet(sniffed_on="eth1")
    d.dispatch(pkt)
    mock_forward.assert_called_once()
    args, _ = mock_forward.call_args
    assert args[1] == "eth2"


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_handle_forwards_from_server_to_client(mock_hwaddr, mock_forward):
    d = Dispatcher(client_iface="eth1", server_iface="eth2")
    pkt = _make_packet(sniffed_on="eth2")
    d.dispatch(pkt)
    mock_forward.assert_called_once()
    args, _ = mock_forward.call_args
    assert args[1] == "eth1"


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_handle_ignores_non_tcp(mock_hwaddr, mock_forward):
    d = Dispatcher()
    pkt = _make_packet(sniffed_on="eth1", has_tcp=False)
    d.dispatch(pkt)
    mock_forward.assert_not_called()


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_handle_unknown_interface(mock_hwaddr, mock_forward):
    d = Dispatcher(client_iface="eth1", server_iface="eth2")
    pkt = _make_packet(sniffed_on="eth0")
    d.dispatch(pkt)
    mock_forward.assert_not_called()


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_custom_interface_names(mock_hwaddr, mock_forward):
    d = Dispatcher(client_iface="ens5", server_iface="ens6")
    pkt = _make_packet(sniffed_on="ens5")
    d.dispatch(pkt)
    mock_forward.assert_called_once()
    args, _ = mock_forward.call_args
    assert args[1] == "ens6"


@patch("src.pipeline.dispatcher.tx.forward")
@patch("src.pipeline.dispatcher.get_if_hwaddr", return_value="aa:bb:cc:dd:ee:ff")
def test_handle_ignores_self_sent_packet(mock_hwaddr, mock_forward):
    d = Dispatcher(client_iface="eth1", server_iface="eth2")
    pkt = _make_packet(sniffed_on="eth1")
    pkt[Ether].src = "aa:bb:cc:dd:ee:ff"  # our own MAC
    d.dispatch(pkt)
    mock_forward.assert_not_called()
