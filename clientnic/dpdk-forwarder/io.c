#include "io.h"
#include "log.h"

#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>

#include <rte_ethdev.h>

/* ── eth0: AF_PACKET raw socket ──────────────────────────────────────────── */

int eth0_init(struct eth0_io *io, const char *iface)
{
    int fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd < 0) {
        LOG_ERR("eth0: socket() failed");
        return -1;
    }

    /* Get interface index */
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, iface, IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFINDEX, &ifr) < 0) {
        LOG_ERR("eth0: SIOCGIFINDEX failed for %s", iface);
        close(fd);
        return -1;
    }
    io->ifindex = ifr.ifr_ifindex;

    /* Bind to interface */
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family   = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex  = io->ifindex;
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
        LOG_ERR("eth0: bind() failed");
        close(fd);
        return -1;
    }

    /* Set non-blocking */
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    /* Read MAC address */
    if (ioctl(fd, SIOCGIFHWADDR, &ifr) < 0) {
        LOG_ERR("eth0: SIOCGIFHWADDR failed");
        close(fd);
        return -1;
    }
    memcpy(io->mac, ifr.ifr_hwaddr.sa_data, 6);

    io->sock_fd = fd;
    LOG_INFO("eth0: initialized on %s (ifindex=%d, MAC=%02x:%02x:%02x:%02x:%02x:%02x)",
             iface, io->ifindex,
             io->mac[0], io->mac[1], io->mac[2],
             io->mac[3], io->mac[4], io->mac[5]);
    return 0;
}

int eth0_recv(struct eth0_io *io, uint8_t *buf, uint16_t buf_size)
{
    ssize_t n = recvfrom(io->sock_fd, buf, buf_size, 0, NULL, NULL);
    if (n <= 0)
        return 0;
    return (int)n;
}

int eth0_send(struct eth0_io *io, const uint8_t *buf, uint16_t len)
{
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family  = AF_PACKET;
    sll.sll_ifindex = io->ifindex;
    sll.sll_halen   = 6;
    memcpy(sll.sll_addr, buf, 6); /* destination MAC from frame */

    ssize_t n = sendto(io->sock_fd, buf, len, 0,
                       (struct sockaddr *)&sll, sizeof(sll));
    return (n == len) ? 0 : -1;
}

/* ── eth1: DPDK ENA PMD ─────────────────────────────────────────────────── */

#define RX_RING_SIZE 1024
#define TX_RING_SIZE 1024

int eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
              const uint8_t *gw_mac)
{
    io->port_id   = port_id;
    io->mbuf_pool = pool;
    memcpy(io->gw_mac, gw_mac, 6);

    if (!rte_eth_dev_is_valid_port(port_id)) {
        LOG_ERR("eth1: DPDK port %u is not valid", port_id);
        return -1;
    }

    struct rte_eth_dev_info dev_info;
    rte_eth_dev_info_get(port_id, &dev_info);

    struct rte_eth_conf port_conf;
    memset(&port_conf, 0, sizeof(port_conf));

    int ret = rte_eth_dev_configure(port_id, 1, 1, &port_conf);
    if (ret < 0) {
        LOG_ERR("eth1: rte_eth_dev_configure failed: %d", ret);
        return -1;
    }

    /* RX queue */
    ret = rte_eth_rx_queue_setup(port_id, 0, RX_RING_SIZE,
                                 rte_eth_dev_socket_id(port_id), NULL, pool);
    if (ret < 0) {
        LOG_ERR("eth1: rx_queue_setup failed: %d", ret);
        return -1;
    }

    /* TX queue */
    struct rte_eth_txconf txconf = dev_info.default_txconf;
    txconf.tx_free_thresh = 32;
    ret = rte_eth_tx_queue_setup(port_id, 0, TX_RING_SIZE,
                                 rte_eth_dev_socket_id(port_id), &txconf);
    if (ret < 0) {
        LOG_ERR("eth1: tx_queue_setup failed: %d", ret);
        return -1;
    }

    ret = rte_eth_dev_start(port_id);
    if (ret < 0) {
        LOG_ERR("eth1: dev_start failed: %d", ret);
        return -1;
    }

    rte_eth_promiscuous_enable(port_id);

    /* Read MAC */
    struct rte_ether_addr addr;
    rte_eth_macaddr_get(port_id, &addr);
    memcpy(io->mac, addr.addr_bytes, 6);

    LOG_INFO("eth1: DPDK port %u started (MAC=%02x:%02x:%02x:%02x:%02x:%02x)",
             port_id,
             io->mac[0], io->mac[1], io->mac[2],
             io->mac[3], io->mac[4], io->mac[5]);
    return 0;
}
