"""ClientNIC entry point."""

import argparse
import logging

from scapy.sendrecv import sniff

from src.utils.logger import setup_logging
from src.utils.flow_table import FlowTable
from src.utils.buffer import PacketBuffer
from src.pipeline.spoofer import SynAckSpoofer
from src.pipeline.syn_handler import SynHandler
from src.pipeline.syn_ack_handler import SynAckHandler
from src.pipeline.translator import Translator
from src.pipeline.dispatcher import Dispatcher


def main():
    parser = argparse.ArgumentParser(description="ClientNIC - 0-RTT TCP middleware")
    parser.add_argument("--client-iface", default="eth0")
    parser.add_argument("--server-iface", default="eth1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    logger = setup_logging(logging.DEBUG if args.verbose else logging.INFO)
    logger.info("Starting ClientNIC (client=%s, server=%s, port=%d)",
                args.client_iface, args.server_iface, args.port)

    flow_table = FlowTable()
    buffer = PacketBuffer()
    spoofer = SynAckSpoofer()

    syn_stage = SynHandler(flow_table, spoofer, args.client_iface, args.server_iface)
    syn_ack_stage = SynAckHandler(flow_table, buffer, args.server_iface)
    translator = Translator(flow_table, buffer, args.client_iface, args.server_iface)
    dispatcher = Dispatcher(syn_stage, syn_ack_stage, translator,
                            flow_table, args.client_iface, args.server_iface)

    bpf = f"tcp port {args.port} and not host 169.254.169.254"
    logger.info("Sniffing on [%s, %s] with filter: %s",
                args.client_iface, args.server_iface, bpf)
    sniff(iface=[args.client_iface, args.server_iface],
          prn=dispatcher.dispatch, filter=bpf, store=False)


if __name__ == "__main__":
    main()
