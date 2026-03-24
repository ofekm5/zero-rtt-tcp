#ifndef TRANSLATOR_H
#define TRANSLATOR_H

#include "flow_table.h"
#include "io.h"

struct translator {
    struct flow_table *ft;
    struct eth0_io    *eth0;
    struct eth1_io    *eth1;
};

void trans_init(struct translator *t, struct flow_table *ft,
                struct eth0_io *eth0, struct eth1_io *eth1);
void trans_c2s(struct translator *t, const uint8_t *pkt, uint16_t len);
void trans_s2c(struct translator *t, struct rte_mbuf *mbuf);

#endif /* TRANSLATOR_H */
