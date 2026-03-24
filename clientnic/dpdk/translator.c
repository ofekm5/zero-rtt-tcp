#include "translator.h"
#include "checksum.h"
#include "log.h"

#include <string.h>
#include <arpa/inet.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

void trans_init(struct translator *t, struct flow_table *ft,
                struct eth0_io *eth0, struct eth1_io *eth1)
{
    t->ft   = ft;
    t->eth0 = eth0;
    t->eth1 = eth1;
}

/* ── Client→Server (eth0 raw buffer → eth1 DPDK) ────────────────────────── */

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
        /* Buffer until delta is known */
        if (ft_buffer_pkt(entry, pkt, len) < 0)
            LOG_WARN("c2s: buffer full, dropping packet");
        return;
    }

    /* Copy packet, rewrite ACK, recalc checksums, send on eth1 */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, pkt, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    struct rte_ipv4_hdr  *ip  = (struct rte_ipv4_hdr *)(buf + 14);
    struct rte_tcp_hdr   *tcp = (struct rte_tcp_hdr *)
                                (buf + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Subtract delta from ACK */
    uint32_t ack = ntohl(tcp->recv_ack);
    tcp->recv_ack = htonl((ack - entry->seq_delta) & 0xFFFFFFFF);

    recalc_ip_checksum(ip);
    recalc_tcp_checksum(ip, tcp);

    /* Rewrite Ether for eth1 */
    memcpy(eth->src_addr.addr_bytes, t->eth1->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, t->eth1->gw_mac, 6);

    /* Send via DPDK */
    struct rte_mbuf *m = rte_pktmbuf_alloc(t->eth1->mbuf_pool);
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

    uint16_t sent = rte_eth_tx_burst(t->eth1->port_id, 0, &m, 1);
    if (sent == 0)
        rte_pktmbuf_free(m);
}

/* ── Server→Client (eth1 mbuf → eth0 raw socket) ────────────────────────── */

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

    /* Copy to stack buffer for modification */
    uint8_t buf[2048];
    if (len > sizeof(buf))
        return;
    memcpy(buf, data, len);

    struct rte_ether_hdr *eth = (struct rte_ether_hdr *)buf;
    struct rte_ipv4_hdr  *ip  = (struct rte_ipv4_hdr *)(buf + 14);
    struct rte_tcp_hdr   *tcp = (struct rte_tcp_hdr *)
                                (buf + 14 + ((ip->version_ihl & 0x0F) * 4));

    /* Add delta to SEQ */
    uint32_t seq = ntohl(tcp->sent_seq);
    tcp->sent_seq = htonl((seq + entry->seq_delta) & 0xFFFFFFFF);

    recalc_ip_checksum(ip);
    recalc_tcp_checksum(ip, tcp);

    /* Rewrite Ether: src=eth0 MAC, dst=client MAC (cached in flow entry) */
    memcpy(eth->src_addr.addr_bytes, t->eth0->mac, 6);
    memcpy(eth->dst_addr.addr_bytes, entry->client_mac, 6);

    /* Send via AF_PACKET */
    eth0_send(t->eth0, buf, len);
}
