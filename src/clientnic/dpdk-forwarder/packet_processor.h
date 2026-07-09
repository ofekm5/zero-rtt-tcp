#ifndef PACKET_PROCESSOR_H
#define PACKET_PROCESSOR_H

#include "flow_table.h"
#include "io.h"

struct packet_processor {
    struct flow_table *ft;
    struct eth0_io    *eth0;
    struct eth1_io    *eth1;
};

void proc_init(struct packet_processor *proc, struct flow_table *ft,
               struct eth0_io *eth0, struct eth1_io *eth1);
void proc_handle_syn(struct packet_processor *proc,
                     const uint8_t *pkt, uint16_t len);

/* proc_handle_syn_ack is absent: the real SYN-ACK is dropped at the ServerNIC */

#endif /* PACKET_PROCESSOR_H */
