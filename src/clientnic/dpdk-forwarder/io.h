#ifndef IO_H
#define IO_H

#include <stdint.h>
#include <rte_mbuf.h>

/* eth0: kernel AF_PACKET raw socket (client-facing) */
struct eth0_io {
    int      sock_fd;
    int      ifindex;
    uint8_t  mac[6];
    uint64_t tx_drops;    /* frames dropped after exhausting send retries */
};

/* eth1: DPDK ENA PMD (server-facing) */
struct eth1_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];
    struct rte_mempool *mbuf_pool;
};

int  eth0_init(struct eth0_io *io, const char *iface);
int  eth0_recv(struct eth0_io *io, uint8_t *buf, uint16_t buf_size);
int  eth0_send(struct eth0_io *io, const uint8_t *buf, uint16_t len);
int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac);

#endif /* IO_H */
