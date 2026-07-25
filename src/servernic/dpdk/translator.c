#include "translator.h"
#include "checksum.h"
#include "log.h"

#include <string.h>
#include <stdio.h>
#include <arpa/inet.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>
#include <rte_cycles.h>
#include <rte_pause.h>

/* TCP application payload length of an IPv4/TCP packet. */
static uint16_t tcp_payload_len(const struct rte_ipv4_hdr *ip,
                                const struct rte_tcp_hdr *tcp)
{
    uint16_t ip_total   = ntohs(ip->total_length);
    uint16_t ip_hdr_len = (ip->version_ihl & 0x0F) * 4;
    uint16_t tcp_hdr    = ((tcp->data_off & 0xF0) >> 4) * 4;
    if (ip_total < ip_hdr_len + tcp_hdr)
        return 0;
    return ip_total - ip_hdr_len - tcp_hdr;
}

/* Emit a parseable per-flow TTFB sample for the experiment harness to aggregate.
 * Interval is intra-host (t0 stamped at SYN ingress) so no clock sync is needed. */
static void log_ttfb(struct flow_entry *entry)
{
    uint64_t cycles = rte_rdtsc() - entry->t0_tsc;
    double   us     = (double)cycles * 1e6 / (double)rte_get_tsc_hz();

    char src[INET_ADDRSTRLEN], dst[INET_ADDRSTRLEN];
    struct in_addr s = { .s_addr = entry->key.src_ip };
    struct in_addr d = { .s_addr = entry->key.dst_ip };
    snprintf(src, sizeof(src), "%s", inet_ntoa(s));
    snprintf(dst, sizeof(dst), "%s", inet_ntoa(d));

    LOG_INFO("[DIAG] ttfb node=servernic flow=%s:%u->%s:%u us=%.1f",
             src, ntohs(entry->key.src_port),
             dst, ntohs(entry->key.dst_port), us);
}

void trans_init(struct translator *t, struct flow_table *ft,
                struct eth1_io *eth1, struct eth2_io *eth2)
{
    t->ft   = ft;
    t->eth1 = eth1;
    t->eth2 = eth2;
}

/* ── Client→Server (eth1 DPDK mbuf → eth2 DPDK port) ─────────────────────── */

void trans_c2s(struct translator *t, const uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    struct flow_key key;
    ft_extract_key(pkt + 14, &key);

    struct flow_entry *entry = ft_lookup(t->ft, &key);
    if (!entry) {
        LOG_WARN("c2s: unknown flow, dropping");
        return;
    }

    if (!entry->delta_valid) {
        /* Buffer until SYN-ACK arrives and delta is computed */
        int brc = ft_buffer_pkt(t->ft, entry, pkt, len);
        if (brc == -2)
            LOG_WARN("c2s: global buffered-bytes ceiling reached (capacity-model §7), dropping packet");
        else if (brc < 0)
            LOG_WARN("c2s: buffer full (flow PENDING), dropping packet");
        return;
    }

    /* Copy, subtract delta from ACK, recompute checksums, forward to Server */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, pkt, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    struct rte_ipv4_hdr  *ip  = (struct rte_ipv4_hdr *)(buf + 14);
    struct rte_tcp_hdr   *tcp = (struct rte_tcp_hdr *)
                                (buf + 14 + ((ip->version_ihl & 0x0F) * 4));

    uint32_t ack = ntohl(tcp->recv_ack);
    tcp->recv_ack = htonl((ack - entry->seq_delta) & 0xFFFFFFFF);

    recalc_ip_checksum(ip);
    recalc_tcp_checksum(ip, tcp);

    memcpy(eth->src_addr.addr_bytes, t->eth2->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, entry->server_mac, 6);

    if (eth2_send(t->eth2, buf, len) < 0)
        LOG_WARN("c2s: eth2_send dropped data segment");
}

/* ── Server→Client (eth2 DPDK mbuf → eth1 DPDK) ───────────────────────────── */

void trans_s2c(struct translator *t, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    /* Reverse key to find the client→server flow entry */
    struct flow_key fwd_key;
    ft_extract_key(data + 14, &fwd_key);
    struct flow_key rev_key;
    ft_reverse_key(&fwd_key, &rev_key);

    struct flow_entry *entry = ft_lookup(t->ft, &rev_key);
    if (!entry || !entry->delta_valid) {
        LOG_WARN("s2c: unknown or incomplete flow, dropping");
        return;
    }

    /* TTFB stop: first server→client segment carrying application payload. */
    if (!entry->ttfb_logged) {
        const struct rte_ipv4_hdr *ip0  = (const struct rte_ipv4_hdr *)(data + 14);
        const struct rte_tcp_hdr  *tcp0 = (const struct rte_tcp_hdr *)
                                          (data + 14 + ((ip0->version_ihl & 0x0F) * 4));
        if (tcp_payload_len(ip0, tcp0) > 0) {
            log_ttfb(entry);
            entry->ttfb_logged = 1;
        }
    }

    /* Copy, add delta to SEQ, recompute checksums, forward toward ClientNIC */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, data, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    struct rte_ipv4_hdr  *ip  = (struct rte_ipv4_hdr *)(buf + 14);
    struct rte_tcp_hdr   *tcp = (struct rte_tcp_hdr *)
                                (buf + 14 + ((ip->version_ihl & 0x0F) * 4));

    uint32_t seq = ntohl(tcp->sent_seq);
    tcp->sent_seq = htonl((seq + entry->seq_delta) & 0xFFFFFFFF);

    recalc_ip_checksum(ip);
    recalc_tcp_checksum(ip, tcp);

    /* Rewrite Ether: src=eth1 MAC, dst=ClientNIC gateway MAC */
    memcpy(eth->src_addr.addr_bytes, t->eth1->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, t->eth1->gw_mac, 6);

    eth1_send(t->eth1, buf, len);
}
