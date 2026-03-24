#ifndef PIPELINE_H
#define PIPELINE_H

#include "packet_processor.h"
#include "translator.h"
#include "io.h"

struct pipeline_ctx {
    struct packet_processor *proc;
    struct translator       *trans;
    struct eth0_io          *eth0;
    struct eth1_io          *eth1;
    uint16_t                 app_port; /* network byte order */
};

void pipeline_init(struct pipeline_ctx *ctx, struct packet_processor *proc,
                   struct translator *trans, struct eth0_io *eth0,
                   struct eth1_io *eth1, uint16_t app_port);
void pipeline_feed_eth0(struct pipeline_ctx *ctx, uint8_t *pkt, uint16_t len);
void pipeline_feed_eth1(struct pipeline_ctx *ctx, struct rte_mbuf *mbuf);

#endif /* PIPELINE_H */
