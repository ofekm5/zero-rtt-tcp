#include "forwarder.h"
#include "log.h"

#include <string.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

void fwd_init(struct forwarder *f, struct flow_table *ft,
              struct eth0_io *eth0, struct eth1_io *eth1)
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

    uint16_t sent = rte_eth_tx_burst(f->eth1->port_id, 0, &m, 1);
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
