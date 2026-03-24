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
        return; /* too short for Ether+IP+TCP */

    /* Parse headers from raw Ethernet frame */
    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)pkt;
    const struct rte_ipv4_hdr  *ip  = (const struct rte_ipv4_hdr *)(pkt + 14);
    const struct rte_tcp_hdr   *tcp = (const struct rte_tcp_hdr *)
                                      (pkt + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Extract flow key */
    struct flow_key key;
    ft_extract_key(pkt + 14, &key);

    /* Check for retransmit */
    if (ft_lookup(proc->ft, &key) != NULL) {
        LOG_DEBUG("SYN retransmit ignored");
        return;
    }

    /* Generate spoofed ISN */
    uint32_t spoofed_isn = (uint32_t)rte_rand();
    uint32_t client_isn  = ntohl(tcp->sent_seq);

    /* Create flow entry with client MAC */
    struct flow_entry *entry = ft_create(proc->ft, &key, client_isn, spoofed_isn,
                                         eth->src_addr.addr_bytes);
    if (!entry) {
        LOG_ERR("SYN: flow table full");
        return;
    }

    /* ── Build and send spoofed SYN-ACK (54 bytes) on eth0 ─────────────── */
    uint8_t sa_buf[54];
    memset(sa_buf, 0, sizeof(sa_buf));

    struct rte_ether_hdr *sa_eth = (struct rte_ether_hdr *)sa_buf;
    struct rte_ipv4_hdr  *sa_ip  = (struct rte_ipv4_hdr *)(sa_buf + 14);
    struct rte_tcp_hdr   *sa_tcp = (struct rte_tcp_hdr *)(sa_buf + 34);

    /* Ether: src=server MAC (incoming dst), dst=client MAC (incoming src) */
    memcpy(sa_eth->dst_addr.addr_bytes, eth->src_addr.addr_bytes, 6);
    memcpy(sa_eth->src_addr.addr_bytes, eth->dst_addr.addr_bytes, 6);
    sa_eth->ether_type = htons(RTE_ETHER_TYPE_IPV4);

    /* IP */
    sa_ip->version_ihl     = 0x45;
    sa_ip->total_length    = htons(40); /* 20 IP + 20 TCP */
    sa_ip->time_to_live    = 64;
    sa_ip->next_proto_id   = IPPROTO_TCP;
    sa_ip->src_addr        = ip->dst_addr;
    sa_ip->dst_addr        = ip->src_addr;

    /* TCP: SYN-ACK */
    sa_tcp->src_port = tcp->dst_port;
    sa_tcp->dst_port = tcp->src_port;
    sa_tcp->sent_seq = htonl(spoofed_isn);
    sa_tcp->recv_ack = htonl((client_isn + 1) & 0xFFFFFFFF);
    sa_tcp->data_off = (5 << 4); /* 20 bytes, no options */
    sa_tcp->tcp_flags = RTE_TCP_SYN_FLAG | RTE_TCP_ACK_FLAG;
    sa_tcp->rx_win   = htons(65535);

    /* Checksums */
    recalc_ip_checksum(sa_ip);
    recalc_tcp_checksum(sa_ip, sa_tcp);

    eth0_send(proc->eth0, sa_buf, 54);

    /* ── Forward original SYN on eth1 (DPDK mbuf) ─────────────────────── */
    struct rte_mbuf *m = rte_pktmbuf_alloc(proc->eth1->mbuf_pool);
    if (!m) {
        LOG_ERR("SYN forward: mbuf alloc failed");
        return;
    }

    /* Build Ethernet frame in mbuf: rewrite Ether header for middle subnet */
    uint8_t *data = rte_pktmbuf_append(m, len);
    if (!data) {
        rte_pktmbuf_free(m);
        return;
    }
    memcpy(data, pkt, len);

    /* Rewrite Ether: src=eth1 MAC, dst=gateway MAC */
    struct rte_ether_hdr *fwd_eth = (struct rte_ether_hdr *)data;
    memcpy(fwd_eth->src_addr.addr_bytes, proc->eth1->mac, 6);
    memcpy(fwd_eth->dst_addr.addr_bytes, proc->eth1->gw_mac, 6);

    uint16_t sent = rte_eth_tx_burst(proc->eth1->port_id, 0, &m, 1);
    if (sent == 0)
        rte_pktmbuf_free(m);

    LOG_INFO("SYN: flow created, spoofed SYN-ACK sent, SYN forwarded");
}

/* ── Real SYN-ACK from server (eth1 mbuf) ────────────────────────────────── */

void proc_handle_syn_ack(struct packet_processor *proc, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    const struct rte_ipv4_hdr *ip  = (const struct rte_ipv4_hdr *)(data + 14);
    const struct rte_tcp_hdr  *tcp = (const struct rte_tcp_hdr *)
                                     (data + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Reverse key: we need client→server direction */
    struct flow_key fwd_key;
    ft_extract_key(data + 14, &fwd_key);
    struct flow_key rev_key;
    ft_reverse_key(&fwd_key, &rev_key);

    struct flow_entry *entry = ft_lookup(proc->ft, &rev_key);
    if (!entry) {
        LOG_WARN("Real SYN-ACK for unknown flow");
        return;
    }

    /* Compute delta */
    uint32_t real_server_isn = ntohl(tcp->sent_seq);
    ft_set_delta(entry, real_server_isn);

    /* Flush buffered packets: rewrite ACK, recalc checksums, send on eth1 */
    struct pkt_buffer bufs[FT_MAX_BUFFER];
    int buf_count = 0;
    ft_flush_buffer(entry, bufs, &buf_count);

    for (int i = 0; i < buf_count; i++) {
        uint8_t *bpkt = bufs[i].data;
        uint16_t blen = bufs[i].len;
        if (blen < 54) {
            free(bpkt);
            continue;
        }

        /* Parse and rewrite ACK */
        struct rte_ipv4_hdr *bip  = (struct rte_ipv4_hdr *)(bpkt + 14);
        struct rte_tcp_hdr  *btcp = (struct rte_tcp_hdr *)
                                    (bpkt + 14 + ((bip->version_ihl & 0x0F) * 4));
        uint32_t ack = ntohl(btcp->recv_ack);
        btcp->recv_ack = htonl((ack - entry->seq_delta) & 0xFFFFFFFF);

        recalc_ip_checksum(bip);
        recalc_tcp_checksum(bip, btcp);

        /* Rewrite Ether for eth1 */
        struct rte_ether_hdr *beth = (struct rte_ether_hdr *)bpkt;
        memcpy(beth->src_addr.addr_bytes, proc->eth1->mac, 6);
        memcpy(beth->dst_addr.addr_bytes, proc->eth1->gw_mac, 6);

        /* Send via DPDK */
        struct rte_mbuf *m = rte_pktmbuf_alloc(proc->eth1->mbuf_pool);
        if (m) {
            uint8_t *d = rte_pktmbuf_append(m, blen);
            if (d) {
                memcpy(d, bpkt, blen);
                uint16_t sent = rte_eth_tx_burst(proc->eth1->port_id, 0, &m, 1);
                if (sent == 0)
                    rte_pktmbuf_free(m);
            } else {
                rte_pktmbuf_free(m);
            }
        }
        free(bpkt);
    }

    LOG_INFO("SYN-ACK: delta=%u, flushed %d buffered pkts", entry->seq_delta, buf_count);
    /* Real SYN-ACK is dropped — client already has the spoofed one */
}
