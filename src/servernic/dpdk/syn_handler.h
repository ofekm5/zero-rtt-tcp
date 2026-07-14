#ifndef SYN_HANDLER_H
#define SYN_HANDLER_H

#include "flow_table.h"
#include "io.h"

struct syn_handler {
    struct flow_table *ft;
    struct eth1_io    *eth1;  /* ClientNIC-facing DPDK port */
    struct eth2_io    *eth2;  /* Server-facing DPDK port */
};

void syn_handler_init(struct syn_handler *sh, struct flow_table *ft,
                      struct eth1_io *eth1, struct eth2_io *eth2);

/* Forwarded SYN from ClientNIC: extract V, zero ack-num, create PENDING flow, forward */
void syn_handler_handle_syn(struct syn_handler *sh,
                            const uint8_t *pkt, uint16_t len);

/* Real SYN-ACK from Server: compute delta, flush buffered pkts, DROP the SYN-ACK */
void syn_handler_handle_syn_ack(struct syn_handler *sh, struct rte_mbuf *mbuf);

#endif /* SYN_HANDLER_H */
