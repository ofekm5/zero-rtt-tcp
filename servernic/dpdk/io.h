#ifndef IO_H
#define IO_H

#include <stdint.h>
#include <rte_mbuf.h>

/* eth1: DPDK ENA PMD (ClientNIC-facing) */
struct eth1_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];   /* ClientNIC-side next-hop MAC (from --gw-mac) */
    struct rte_mempool *mbuf_pool;
};

/* eth2: AF_PACKET raw socket (Server-facing) */
struct eth2_io {
    int      sock_fd;
    int      ifindex;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];   /* Server-side next-hop MAC (from --server-gw-mac) */
};

int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac);
int  eth2_init(struct eth2_io *io, const char *iface, const uint8_t *gw_mac);
int  eth2_recv(struct eth2_io *io, uint8_t *buf, uint16_t buf_size);
int  eth2_send(struct eth2_io *io, const uint8_t *buf, uint16_t len);

#endif /* IO_H */
