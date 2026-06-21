#ifndef PIPELINE_H
#define PIPELINE_H

#include "syn_handler.h"
#include "translator.h"
#include "io.h"

struct pipeline_ctx {
    struct syn_handler *sh;
    struct translator  *trans;
    struct eth1_io     *eth1;
    struct eth2_io     *eth2;
    uint16_t            app_port_base;  /* host byte order, inclusive low  */
    uint16_t            app_port_count; /* number of contiguous app ports  */
};

void pipeline_init(struct pipeline_ctx *ctx, struct syn_handler *sh,
                   struct translator *trans, struct eth1_io *eth1,
                   struct eth2_io *eth2, uint16_t app_port_base,
                   uint16_t app_port_count);

/* eth1 ingress (DPDK mbuf from ClientNIC) */
void pipeline_feed_eth1(struct pipeline_ctx *ctx, struct rte_mbuf *mbuf);

/* eth2 ingress (AF_PACKET raw buf from Server) */
void pipeline_feed_eth2(struct pipeline_ctx *ctx, uint8_t *pkt, uint16_t len);

#endif /* PIPELINE_H */
