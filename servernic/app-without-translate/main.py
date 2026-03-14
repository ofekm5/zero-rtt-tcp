"""ServerNIC entry point."""
import argparse
import logging

from scapy.sendrecv import sniff

from src.utils.logger import setup_logging
from src.pipeline.dispatcher import Dispatcher


def main():
    parser = argparse.ArgumentParser(description="ServerNIC - stateless packet forwarder")
    parser.add_argument("--client-iface", default="eth1", help="Interface facing ClientNIC (default: eth1)")
    parser.add_argument("--server-iface", default="eth2", help="Interface facing Server (default: eth2)")
    parser.add_argument("--port", type=int, default=8080, help="TCP port to filter (default: 8080)")
    parser.add_argument("--verbose", action="store_true", help="Enable DEBUG logging")
    args = parser.parse_args()

    logger = setup_logging(logging.DEBUG if args.verbose else logging.INFO)
    logger.info("Starting ServerNIC...")
    logger.info("Forwarding between %s (ClientNIC) <-> %s (Server)", args.client_iface, args.server_iface)

    dispatcher = Dispatcher(client_iface=args.client_iface, server_iface=args.server_iface)

    bpf = f"tcp port {args.port} and not host 169.254.169.254"
    logger.info("Sniffing on [%s, %s] with filter: %s", args.client_iface, args.server_iface, bpf)
    sniff(
        iface=[args.client_iface, args.server_iface],
        prn=dispatcher.dispatch,
        filter=bpf,
        store=False,
    )


if __name__ == "__main__":
    main()
