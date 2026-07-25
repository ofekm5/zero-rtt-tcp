#include "syn_handler.h"
#include "checksum.h"
#include "log.h"

#include <string.h>
#include <stdlib.h>
#include <arpa/inet.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

void syn_handler_init(struct syn_handler *sh, struct flow_table *ft,
                      struct eth1_io *eth1, struct eth2_io *eth2)
{
    sh->ft   = ft;
    sh->eth1 = eth1;
    sh->eth2 = eth2;
}

/* ── Forwarded SYN from ClientNIC (eth1 DPDK mbuf) ──────────────────────── */

void syn_handler_handle_syn(struct syn_handler *sh,
                            const uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    const struct rte_ipv4_hdr *ip  = (const struct rte_ipv4_hdr *)(pkt + 14);
    const struct rte_tcp_hdr  *tcp = (const struct rte_tcp_hdr *)
                                     (pkt + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Read V from ack-num field (stamped by the ClientNIC forwarder) */
    uint32_t V = ntohl(tcp->recv_ack);

    struct flow_key key;
    ft_extract_key(pkt + 14, &key);

    /* Create or refresh PENDING entry */
    struct flow_entry *entry = ft_lookup(sh->ft, &key);
    if (!entry) {
        /* Server-side next-hop MAC: use eth2's configured server peer MAC */
        entry = ft_create(sh->ft, &key, V, sh->eth2->server_mac);
        if (!entry) {
            LOG_ERR("SYN: flow table full");
            return;
        }
        LOG_INFO("SYN: new flow, V=0x%08x", V);
    } else {
        /* Retransmit: retain existing PENDING entry, update V if needed */
        LOG_DEBUG("SYN retransmit: flow exists, V=0x%08x", V);
    }

    /* Copy packet, zero ack-num, recompute TCP checksum, forward to Server */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, pkt, len);

    struct rte_ether_hdr *fwd_eth = (struct rte_ether_hdr *)buf;
    struct rte_ipv4_hdr  *fwd_ip  = (struct rte_ipv4_hdr *)(buf + 14);
    struct rte_tcp_hdr   *fwd_tcp = (struct rte_tcp_hdr *)
                                    (buf + 14 + ((fwd_ip->version_ihl & 0x0F) * 4));

    /* Zero ack-num before forwarding to Server (keeps wire RFC-clean) */
    fwd_tcp->recv_ack = 0;
    recalc_tcp_checksum(fwd_ip, fwd_tcp);

    /* Rewrite Ether: src=eth2 MAC, dst=server peer MAC */
    memcpy(fwd_eth->src_addr.addr_bytes, sh->eth2->mac, 6);
    memcpy(fwd_eth->dst_addr.addr_bytes, sh->eth2->server_mac, 6);

    eth2_send(sh->eth2, buf, len);
    LOG_DEBUG("SYN forwarded to Server (ack-num zeroed)");
}

/* ── Real SYN-ACK from Server (eth2 DPDK mbuf) ───────────────────────────── */

void syn_handler_handle_syn_ack(struct syn_handler *sh, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    const struct rte_ipv4_hdr *ip  = (const struct rte_ipv4_hdr *)(data + 14);
    const struct rte_tcp_hdr  *tcp = (const struct rte_tcp_hdr *)
                                     (data + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Reverse key: SYN-ACK is server→client, we need client→server entry */
    struct flow_key fwd_key;
    ft_extract_key(data + 14, &fwd_key);
    struct flow_key rev_key;
    ft_reverse_key(&fwd_key, &rev_key);

    struct flow_entry *entry = ft_lookup(sh->ft, &rev_key);
    if (!entry) {
        LOG_WARN("SYN-ACK: unknown flow, dropping");
        return; /* drop */
    }

    uint32_t real_isn = ntohl(tcp->sent_seq);
    int newly_active  = ft_set_delta(entry, real_isn);

    if (newly_active) {
        LOG_INFO("SYN-ACK: delta=0x%08x, V=0x%08x, real_isn=0x%08x",
                 entry->seq_delta, entry->spoofed_server_isn, real_isn);
    }

    /* Flush buffered client→server packets: rewrite ACK - delta, recalc checksums */
    struct pkt_buffer bufs[FT_MAX_BUFFER];
    int buf_count = 0;
    ft_flush_buffer(sh->ft, entry, bufs, &buf_count);

    for (int i = 0; i < buf_count; i++) {
        uint8_t *bpkt = bufs[i].data;
        uint16_t blen = bufs[i].len;
        if (blen < 54) {
            free(bpkt);
            continue;
        }

        struct rte_ipv4_hdr *bip  = (struct rte_ipv4_hdr *)(bpkt + 14);
        struct rte_tcp_hdr  *btcp = (struct rte_tcp_hdr *)
                                    (bpkt + 14 + ((bip->version_ihl & 0x0F) * 4));

        uint32_t ack = ntohl(btcp->recv_ack);
        btcp->recv_ack = htonl((ack - entry->seq_delta) & 0xFFFFFFFF);

        recalc_ip_checksum(bip);
        recalc_tcp_checksum(bip, btcp);

        /* Rewrite Ether for eth2 */
        struct rte_ether_hdr *beth = (struct rte_ether_hdr *)bpkt;
        memcpy(beth->src_addr.addr_bytes, sh->eth2->mac, 6);
        memcpy(beth->dst_addr.addr_bytes, entry->server_mac, 6);

        /* This is the FIRST 0-RTT client data. A drop here is the direct cause
         * of the bimodal ~200ms server_gap, so surface it. */
        if (eth2_send(sh->eth2, bpkt, blen) < 0)
            LOG_WARN("SYN-ACK: flush dropped first c2s data");
        free(bpkt);
    }

    if (buf_count > 0)
        LOG_INFO("SYN-ACK: flushed %d buffered c2s packets", buf_count);

    /* Drop the real SYN-ACK — client already has the spoofed one from ClientNIC */
    LOG_DEBUG("SYN-ACK dropped (client has spoofed one)");
}
