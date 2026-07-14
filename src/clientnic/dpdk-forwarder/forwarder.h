#ifndef FORWARDER_H
#define FORWARDER_H

#include "flow_table.h"
#include "io.h"

struct forwarder {
    struct flow_table *ft;
    struct client_io  *eth0;
    struct eth1_io    *eth1;
};

void fwd_init(struct forwarder *f, struct flow_table *ft,
              struct client_io *eth0, struct eth1_io *eth1);
void forward_c2s(struct forwarder *f, const uint8_t *pkt, uint16_t len);
void forward_s2c(struct forwarder *f, struct rte_mbuf *mbuf);

#endif /* FORWARDER_H */
