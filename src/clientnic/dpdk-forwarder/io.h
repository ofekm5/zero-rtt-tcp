#ifndef IO_H
#define IO_H

#include <stdint.h>
#include <rte_mbuf.h>

/* eth0: DPDK ENA PMD (client-facing) */
struct client_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  client_mac[6];   /* configured client peer MAC (destination for TX) */
    struct rte_mempool *mbuf_pool;
};

/* eth1: DPDK ENA PMD (server-facing) */
struct eth1_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];
    struct rte_mempool *mbuf_pool;
};

int  eth0_init(struct client_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *client_mac);
int  eth0_send(struct client_io *io, const uint8_t *buf, uint16_t len);
int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac);

#endif /* IO_H */
