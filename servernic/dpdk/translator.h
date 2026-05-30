#ifndef TRANSLATOR_H
#define TRANSLATOR_H

#include "flow_table.h"
#include "io.h"

struct translator {
    struct flow_table *ft;
    struct eth1_io    *eth1;  /* ClientNIC-facing DPDK port */
    struct eth2_io    *eth2;  /* Server-facing AF_PACKET socket */
};

void trans_init(struct translator *t, struct flow_table *ft,
                struct eth1_io *eth1, struct eth2_io *eth2);

/* eth1 non-SYN: subtract delta from ACK, forward to Server (eth2) */
void trans_c2s(struct translator *t, const uint8_t *pkt, uint16_t len);

/* eth2 non-SYN-ACK: add delta to SEQ, forward toward ClientNIC (eth1) */
void trans_s2c(struct translator *t, struct rte_mbuf *mbuf);

#endif /* TRANSLATOR_H */
