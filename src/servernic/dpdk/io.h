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

/* eth2: DPDK ENA PMD (Server-facing) */
struct eth2_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  server_mac[6];   /* configured Server peer MAC (from --server-mac) */
    struct rte_mempool *mbuf_pool;
};

/* Resolve the DPDK port whose own MAC equals `mac`.
 *
 * Port IDs are assigned in PCI-enumeration order, which does NOT reliably track
 * ENI device_index — the Middle-subnet and Server-subnet ENIs can appear in
 * either order. Binding a role to a hardcoded port ID therefore silently swaps
 * the two links. Callers pass the expected local ENI MAC instead. */
int  io_find_port_by_mac(const uint8_t *mac, uint16_t *port_id);

int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac);
int  eth2_init(struct eth2_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *server_mac);
int  eth2_send(struct eth2_io *io, const uint8_t *buf, uint16_t len);

#endif /* IO_H */
