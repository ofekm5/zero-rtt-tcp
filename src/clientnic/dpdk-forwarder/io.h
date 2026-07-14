#ifndef IO_H
#define IO_H

#include <stdint.h>
#include <rte_mbuf.h>

/* eth0: DPDK ENA PMD (client-facing) */
struct client_io {
    uint16_t port_id;
    uint8_t  mac[6];
    struct rte_mempool *mbuf_pool;
};

/* eth1: DPDK ENA PMD (server-facing) */
struct eth1_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];
    struct rte_mempool *mbuf_pool;
};

/* Resolve the DPDK port whose own MAC equals `mac`.
 *
 * Port IDs are assigned in PCI-enumeration order, which does NOT reliably track
 * ENI device_index — the Client-subnet and Middle-subnet ENIs can appear in
 * either order. Binding a role to a hardcoded port ID therefore silently swaps
 * the two links. Callers pass the expected local ENI MAC instead. */
int  io_find_port_by_mac(const uint8_t *mac, uint16_t *port_id);

int  eth0_init(struct client_io *io, uint16_t port_id, struct rte_mempool *pool);
int  eth0_send(struct client_io *io, const uint8_t *buf, uint16_t len);
int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac);

#endif /* IO_H */
