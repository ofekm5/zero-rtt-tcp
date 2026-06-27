#include "packet_processor.h"
#include "checksum.h"
#include "log.h"

#include <string.h>
#include <arpa/inet.h>
#include <rte_random.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>
#include <rte_pause.h>

void proc_init(struct packet_processor *proc, struct flow_table *ft,
               struct eth0_io *eth0, struct eth1_io *eth1)
{
    proc->ft   = ft;
    proc->eth0 = eth0;
    proc->eth1 = eth1;
}

/* ── SYN from client (eth0 raw buffer) ───────────────────────────────────── */

void proc_handle_syn(struct packet_processor *proc,
                     const uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)pkt;
    const struct rte_ipv4_hdr  *ip  = (const struct rte_ipv4_hdr *)(pkt + 14);
    const struct rte_tcp_hdr   *tcp = (const struct rte_tcp_hdr *)
                                      (pkt + 14 + ((ip->version_ihl & 0x0F) * 4));

    struct flow_key key;
    ft_extract_key(pkt + 14, &key);

    uint32_t spoofed_isn;

    struct flow_entry *entry = ft_lookup(proc->ft, &key);
    if (entry) {
        /* Retransmit: re-use the same V already chosen for this flow */
        spoofed_isn = entry->spoofed_server_isn;
        LOG_DEBUG("SYN retransmit: re-stamping V=0x%08x", spoofed_isn);
    } else {
        /* First SYN: generate V and create flow entry */
        spoofed_isn = (uint32_t)rte_rand();
        uint32_t client_isn = ntohl(tcp->sent_seq);
        (void)client_isn; /* only needed for the spoofed SYN-ACK ack field */

        entry = ft_create(proc->ft, &key, spoofed_isn, eth->src_addr.addr_bytes);
        if (!entry) {
            LOG_ERR("SYN: flow table full");
            return;
        }

        /* ── Build and send spoofed SYN-ACK (54 bytes) on eth0 ─────────── */
        uint8_t sa_buf[54];
        memset(sa_buf, 0, sizeof(sa_buf));

        struct rte_ether_hdr *sa_eth = (struct rte_ether_hdr *)sa_buf;
        struct rte_ipv4_hdr  *sa_ip  = (struct rte_ipv4_hdr *)(sa_buf + 14);
        struct rte_tcp_hdr   *sa_tcp = (struct rte_tcp_hdr *)(sa_buf + 34);

        memcpy(sa_eth->dst_addr.addr_bytes, eth->src_addr.addr_bytes, 6);
        memcpy(sa_eth->src_addr.addr_bytes, eth->dst_addr.addr_bytes, 6);
        sa_eth->ether_type = htons(RTE_ETHER_TYPE_IPV4);

        sa_ip->version_ihl   = 0x45;
        sa_ip->total_length  = htons(40);
        sa_ip->time_to_live  = 64;
        sa_ip->next_proto_id = IPPROTO_TCP;
        sa_ip->src_addr      = ip->dst_addr;
        sa_ip->dst_addr      = ip->src_addr;

        sa_tcp->src_port  = tcp->dst_port;
        sa_tcp->dst_port  = tcp->src_port;
        sa_tcp->sent_seq  = htonl(spoofed_isn);
        sa_tcp->recv_ack  = htonl((ntohl(tcp->sent_seq) + 1) & 0xFFFFFFFF);
        sa_tcp->data_off  = (5 << 4);
        sa_tcp->tcp_flags = RTE_TCP_SYN_FLAG | RTE_TCP_ACK_FLAG;
        sa_tcp->rx_win    = htons(65535);

        recalc_ip_checksum(sa_ip);
        recalc_tcp_checksum(sa_ip, sa_tcp);

        eth0_send(proc->eth0, sa_buf, 54);
    }

    /* ── Forward original SYN on eth1 with V stamped in ack-num ─────────── */
    struct rte_mbuf *m = rte_pktmbuf_alloc(proc->eth1->mbuf_pool);
    if (!m) {
        LOG_ERR("SYN forward: mbuf alloc failed");
        return;
    }

    uint8_t *data = rte_pktmbuf_append(m, len);
    if (!data) {
        rte_pktmbuf_free(m);
        return;
    }
    memcpy(data, pkt, len);

    /* Rewrite Ether header for middle subnet */
    struct rte_ether_hdr *fwd_eth = (struct rte_ether_hdr *)data;
    memcpy(fwd_eth->src_addr.addr_bytes, proc->eth1->mac, 6);
    memcpy(fwd_eth->dst_addr.addr_bytes, proc->eth1->gw_mac, 6);

    /* Stamp V into the forwarded SYN's ack-num field (task 3.1).
     * RFC 9293 §3.10.7.2: a LISTEN-state endpoint ignores ack_seq when ACK
     * flag is clear, so this field is free real estate on a pure SYN.
     * The ServerNIC reads V here, zeros this field, and forwards a clean SYN. */
    struct rte_ipv4_hdr *fwd_ip  = (struct rte_ipv4_hdr *)(data + 14);
    struct rte_tcp_hdr  *fwd_tcp = (struct rte_tcp_hdr *)
                                   (data + 14 + ((fwd_ip->version_ihl & 0x0F) * 4));
    fwd_tcp->recv_ack = htonl(spoofed_isn);
    recalc_tcp_checksum(fwd_ip, fwd_tcp);

    /* A dropped SYN costs a ~1s connect RTO; retry briefly if the ring is full. */
    uint16_t sent = 0;
    for (int attempt = 0; attempt < 1000; attempt++) {
        sent = rte_eth_tx_burst(proc->eth1->port_id, 0, &m, 1);
        if (sent)
            break;
        rte_pause();
    }
    if (sent == 0)
        rte_pktmbuf_free(m);

    LOG_INFO("SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x%08x in ack-num",
             spoofed_isn);
}
