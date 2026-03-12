"""ClientNIC entry point."""

import threading

from scapy.layers.l2 import get_if_hwaddr
from scapy.sendrecv import sniff

from .src.logger import setup_logging
from .src.flow_table import FlowTable
from .src.spoofer import SynAckSpoofer
from .src.rewriter import PacketRewriter
from .src.handlers import PacketBuffer, ClientPacketHandler, ServerPacketHandler

CLIENT_IFACE = "eth0"
SERVER_IFACE = "eth1"


def main():
    """Start ClientNIC packet capture and processing."""
    logger = setup_logging()
    logger.info("Starting ClientNIC...")

    # Collect our own MAC addresses so handlers can skip self-sent packets
    our_macs = set()
    for iface in (CLIENT_IFACE, SERVER_IFACE):
        try:
            our_macs.add(get_if_hwaddr(iface).lower())
        except Exception:
            pass
    logger.info("Our MACs: %s", our_macs)

    # Create shared instances
    flow_table = FlowTable()
    spoofer = SynAckSpoofer()
    rewriter = PacketRewriter()
    buffer = PacketBuffer()

    # Create handlers
    client_handler = ClientPacketHandler(
        flow_table=flow_table,
        spoofer=spoofer,
        rewriter=rewriter,
        buffer=buffer,
        client_iface=CLIENT_IFACE,
        server_iface=SERVER_IFACE,
        our_macs=our_macs,
    )
    server_handler = ServerPacketHandler(
        flow_table=flow_table,
        rewriter=rewriter,
        buffer=buffer,
        client_iface=CLIENT_IFACE,
        server_iface=SERVER_IFACE,
        our_macs=our_macs,
    )

    # Sniff eth1 (server-side) in background thread
    logger.info("Sniffing on %s...", SERVER_IFACE)
    eth1_thread = threading.Thread(
        target=sniff,
        kwargs=dict(
            iface=SERVER_IFACE,
            prn=server_handler.handle,
            filter="tcp port 8080",
            store=False,
        ),
        daemon=True,
    )
    eth1_thread.start()

    # Sniff eth0 (client-side) in main thread
    logger.info("Sniffing on %s...", CLIENT_IFACE)
    sniff(
        iface=CLIENT_IFACE,
        prn=client_handler.handle,
        filter="tcp port 8080",
        store=False,
    )


if __name__ == "__main__":
    main()
