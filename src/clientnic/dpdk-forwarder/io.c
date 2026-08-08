#include "io.h"
#include "log.h"

#include <string.h>

#include <rte_ethdev.h>
#include <rte_pause.h>
#include <rte_mbuf.h>

/* Bounded TX-burst retries on a momentarily full ring. Kept small: on the
 * single-threaded poll loop a long spin causes head-of-line blocking that
 * collapses throughput under load. Drop after a few and let TCP retransmit. */
#define ETH0_TX_RETRIES 8

#define RX_RING_SIZE 1024
#define TX_RING_SIZE 1024

/* ── Port lookup by local MAC ────────────────────────────────────────────── */

int io_find_port_by_mac(const uint8_t *mac, uint16_t *port_id)
{
    uint16_t pid;

    RTE_ETH_FOREACH_DEV(pid) {
        struct rte_ether_addr addr;
        if (rte_eth_macaddr_get(pid, &addr) < 0)
            continue;
        if (memcmp(addr.addr_bytes, mac, 6) == 0) {
            *port_id = pid;
            return 0;
        }
    }
    return -1;
}

/* ── eth0: DPDK ENA PMD (client-facing) ──────────────────────────────────── */

int eth0_init(struct client_io *io, uint16_t port_id, struct rte_mempool *pool)
{
    io->port_id   = port_id;
    io->mbuf_pool = pool;

    if (!rte_eth_dev_is_valid_port(port_id)) {
        LOG_ERR("eth0: DPDK port %u is not valid", port_id);
        return -1;
    }

    struct rte_eth_dev_info dev_info;
    rte_eth_dev_info_get(port_id, &dev_info);

    struct rte_eth_conf port_conf;
    memset(&port_conf, 0, sizeof(port_conf));

    int ret = rte_eth_dev_configure(port_id, 1, 1, &port_conf);
    if (ret < 0) {
        LOG_ERR("eth0: rte_eth_dev_configure failed: %d", ret);
        return -1;
    }

    /* RX queue */
    ret = rte_eth_rx_queue_setup(port_id, 0, RX_RING_SIZE,
                                 rte_eth_dev_socket_id(port_id), NULL, pool);
    if (ret < 0) {
        LOG_ERR("eth0: rx_queue_setup failed: %d", ret);
        return -1;
    }

    /* TX queue */
    struct rte_eth_txconf txconf = dev_info.default_txconf;
    txconf.tx_free_thresh = 32;
    ret = rte_eth_tx_queue_setup(port_id, 0, TX_RING_SIZE,
                                 rte_eth_dev_socket_id(port_id), &txconf);
    if (ret < 0) {
        LOG_ERR("eth0: tx_queue_setup failed: %d", ret);
        return -1;
    }

    ret = rte_eth_dev_start(port_id);
    if (ret < 0) {
        LOG_ERR("eth0: dev_start failed: %d", ret);
        return -1;
    }

    rte_eth_promiscuous_enable(port_id);

    /* Read MAC */
    struct rte_ether_addr addr;
    rte_eth_macaddr_get(port_id, &addr);
    memcpy(io->mac, addr.addr_bytes, 6);

    LOG_INFO("eth0: DPDK port %u started, client-facing "
             "(MAC=%02x:%02x:%02x:%02x:%02x:%02x)",
             port_id,
             io->mac[0], io->mac[1], io->mac[2],
             io->mac[3], io->mac[4], io->mac[5]);
    return 0;
}

/* Flush whatever is queued in one rte_eth_tx_burst() call. Retries briefly on
 * a momentarily-full ring, then frees whatever the ring never accepted. */
void eth0_tx_flush(struct client_io *io)
{
    if (io->tx_batch_count == 0)
        return;

    uint16_t sent = 0;
    for (int attempt = 0; attempt < ETH0_TX_RETRIES && sent < io->tx_batch_count; attempt++) {
        sent += rte_eth_tx_burst(io->port_id, 0, io->tx_batch + sent,
                                 io->tx_batch_count - sent);
        if (sent < io->tx_batch_count)
            rte_pause();
    }
    for (uint16_t i = sent; i < io->tx_batch_count; i++)
        rte_pktmbuf_free(io->tx_batch[i]);
    io->tx_batch_count = 0;
}

int eth0_send(struct client_io *io, const uint8_t *buf, uint16_t len)
{
    struct rte_mbuf *m = rte_pktmbuf_alloc(io->mbuf_pool);
    if (!m) {
        LOG_ERR("eth0: mbuf alloc failed");
        return -1;
    }

    uint8_t *data = rte_pktmbuf_append(m, len);
    if (!data) {
        rte_pktmbuf_free(m);
        return -1;
    }
    memcpy(data, buf, len);

    io->tx_batch[io->tx_batch_count++] = m;
    if (io->tx_batch_count >= TX_BATCH_SIZE)
        eth0_tx_flush(io);
    return 0;
}

/* ── eth1: DPDK ENA PMD (ServerNIC-facing) ──────────────────────────────── */

int eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
              const uint8_t *gw_mac, uint32_t wan_delay_us)
{
    io->port_id   = port_id;
    io->mbuf_pool = pool;
    memcpy(io->gw_mac, gw_mac, 6);
    wan_delay_init(&io->wan, wan_delay_us);

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

    LOG_INFO("eth1: DPDK port %u started, ServerNIC-facing "
             "(MAC=%02x:%02x:%02x:%02x:%02x:%02x, gw=%02x:%02x:%02x:%02x:%02x:%02x)",
             port_id,
             io->mac[0], io->mac[1], io->mac[2],
             io->mac[3], io->mac[4], io->mac[5],
             io->gw_mac[0], io->gw_mac[1], io->gw_mac[2],
             io->gw_mac[3], io->gw_mac[4], io->gw_mac[5]);
    return 0;
}

void eth1_tx_flush(struct eth1_io *io)
{
    if (io->tx_batch_count == 0)
        return;

    uint16_t sent = 0;
    for (int attempt = 0; attempt < ETH0_TX_RETRIES && sent < io->tx_batch_count; attempt++) {
        sent += rte_eth_tx_burst(io->port_id, 0, io->tx_batch + sent,
                                 io->tx_batch_count - sent);
        if (sent < io->tx_batch_count)
            rte_pause();
    }
    for (uint16_t i = sent; i < io->tx_batch_count; i++)
        rte_pktmbuf_free(io->tx_batch[i]);
    io->tx_batch_count = 0;
}

int eth1_send(struct eth1_io *io, const uint8_t *buf, uint16_t len)
{
    struct rte_mbuf *m = rte_pktmbuf_alloc(io->mbuf_pool);
    if (!m) {
        LOG_ERR("eth1: mbuf alloc failed");
        return -1;
    }

    uint8_t *data = rte_pktmbuf_append(m, len);
    if (!data) {
        rte_pktmbuf_free(m);
        return -1;
    }
    memcpy(data, buf, len);

    /* Middle leg: hold for the emulated WAN before it may go out. The mbuf is
     * handed to the queue, which owns it from here (including on drop). */
    if (wan_delay_enabled(&io->wan))
        return wan_delay_push(&io->wan, m);

    io->tx_batch[io->tx_batch_count++] = m;
    if (io->tx_batch_count >= TX_BATCH_SIZE)
        eth1_tx_flush(io);
    return 0;
}

void eth1_wan_service(struct eth1_io *io)
{
    if (!wan_delay_enabled(&io->wan))
        return;

    for (;;) {
        uint16_t room = TX_BATCH_SIZE - io->tx_batch_count;
        if (room == 0) {
            eth1_tx_flush(io);
            room = TX_BATCH_SIZE;
        }
        uint16_t n = wan_delay_pop_expired(&io->wan,
                                           io->tx_batch + io->tx_batch_count,
                                           room);
        if (n == 0)
            break;
        io->tx_batch_count = (uint16_t)(io->tx_batch_count + n);
    }
}

void eth1_wan_flush_all(struct eth1_io *io)
{
    if (!wan_delay_enabled(&io->wan))
        return;

    for (;;) {
        eth1_tx_flush(io);
        uint16_t n = wan_delay_drain_all(&io->wan, io->tx_batch, TX_BATCH_SIZE);
        if (n == 0)
            break;
        io->tx_batch_count = n;
    }
}
