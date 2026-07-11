#include "forwarder.h"
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

/* TCP application payload length of an IPv4/TCP packet at `l3` (start of IP hdr). */
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

    LOG_INFO("[DIAG] ttfb node=clientnic flow=%s:%u->%s:%u us=%.1f",
             src, ntohs(entry->key.src_port),
             dst, ntohs(entry->key.dst_port), us);
}

void fwd_init(struct forwarder *f, struct flow_table *ft,
              struct client_io *eth0, struct eth1_io *eth1)
{
    f->ft   = ft;
    f->eth0 = eth0;
    f->eth1 = eth1;
}

/* ── Client→Server transparent forward (eth0 raw → eth1 DPDK) ───────────── */

void forward_c2s(struct forwarder *f, const uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    struct flow_key key;
    ft_extract_key(pkt + 14, &key);

    struct flow_entry *entry = ft_lookup(f->ft, &key);
    if (!entry) {
        LOG_WARN("c2s: unknown flow, dropping");
        return;
    }

    /* Copy packet: only rewrite Ethernet header, no seq/ack changes.
     * Seq/ack translation is handled downstream by the ServerNIC. */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, pkt, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    memcpy(eth->src_addr.addr_bytes, f->eth1->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, f->eth1->gw_mac, 6);

    struct rte_mbuf *m = rte_pktmbuf_alloc(f->eth1->mbuf_pool);
    if (!m) {
        LOG_ERR("c2s: mbuf alloc failed");
        return;
    }
    uint8_t *data = rte_pktmbuf_append(m, len);
    if (!data) {
        rte_pktmbuf_free(m);
        return;
    }
    memcpy(data, buf, len);

    /* Bulk c2s egress: retry briefly if the TX ring is momentarily full
     * instead of silently dropping (a drop here -> client TCP RTO). */
    uint16_t sent = 0;
    for (int attempt = 0; attempt < 8; attempt++) {
        sent = rte_eth_tx_burst(f->eth1->port_id, 0, &m, 1);
        if (sent)
            break;
        rte_pause();
    }
    if (sent == 0)
        rte_pktmbuf_free(m);
}

/* ── Server→Client transparent forward (eth1 DPDK → eth0 raw) ───────────── */

void forward_s2c(struct forwarder *f, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    /* Reverse key to find the client→server flow entry (for client_mac) */
    struct flow_key fwd_key;
    ft_extract_key(data + 14, &fwd_key);
    struct flow_key rev_key;
    ft_reverse_key(&fwd_key, &rev_key);

    struct flow_entry *entry = ft_lookup(f->ft, &rev_key);
    if (!entry) {
        LOG_WARN("s2c: unknown flow, dropping");
        return;
    }

    /* TTFB stop: first server→client segment carrying application payload. */
    if (!entry->ttfb_logged) {
        const struct rte_ipv4_hdr *ip  = (const struct rte_ipv4_hdr *)(data + 14);
        const struct rte_tcp_hdr  *tcp = (const struct rte_tcp_hdr *)
                                         (data + 14 + ((ip->version_ihl & 0x0F) * 4));
        if (tcp_payload_len(ip, tcp) > 0) {
            log_ttfb(entry);
            entry->ttfb_logged = 1;
        }
    }

    /* Copy packet: only rewrite Ethernet header, no seq/ack changes.
     * The ServerNIC has already translated the SEQ before forwarding. */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, data, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    memcpy(eth->src_addr.addr_bytes, f->eth0->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, entry->client_mac, 6);

    eth0_send(f->eth0, buf, len);
}
