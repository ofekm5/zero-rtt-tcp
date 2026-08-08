#ifndef IO_H
#define IO_H

#include <stdint.h>
#include <rte_mbuf.h>

#include "wan_delay.h"

/* Packets accumulate here across a poll-loop iteration and go out in one
 * rte_eth_tx_burst() call instead of one doorbell write per packet — the
 * classic one-at-a-time TX anti-pattern flagged in capacity-model.md §4/§9. */
#define TX_BATCH_SIZE 32

/* eth0: DPDK ENA PMD (client-facing) */
struct client_io {
    uint16_t port_id;
    uint8_t  mac[6];
    struct rte_mempool *mbuf_pool;
    struct rte_mbuf *tx_batch[TX_BATCH_SIZE];
    uint16_t tx_batch_count;
};

/* eth1: DPDK ENA PMD (server-facing) — this is the middle leg, so it carries
 * the emulated WAN delay (roadmap.md F2). */
struct eth1_io {
    uint16_t port_id;
    uint8_t  mac[6];
    uint8_t  gw_mac[6];
    struct rte_mempool *mbuf_pool;
    struct rte_mbuf *tx_batch[TX_BATCH_SIZE];
    uint16_t tx_batch_count;
    struct wan_delay wan;
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
void eth0_tx_flush(struct client_io *io);
/* wan_delay_us: emulated one-way WAN latency on the ClientNIC→ServerNIC leg.
 * 0 disables the hold queue entirely and eth1_send() goes straight to TX. */
int  eth1_init(struct eth1_io *io, uint16_t port_id, struct rte_mempool *pool,
               const uint8_t *gw_mac, uint32_t wan_delay_us);
int  eth1_send(struct eth1_io *io, const uint8_t *buf, uint16_t len);
void eth1_tx_flush(struct eth1_io *io);

/* Move packets whose WAN hold has expired into the TX batch. Must be called
 * every poll-loop iteration when the WAN delay is enabled, otherwise held
 * packets are never released. No-op when disabled. */
void eth1_wan_service(struct eth1_io *io);

/* Release everything still held and flush. Shutdown path only. */
void eth1_wan_flush_all(struct eth1_io *io);

#endif /* IO_H */
