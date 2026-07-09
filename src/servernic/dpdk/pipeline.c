#include "pipeline.h"
#include "log.h"

#include <string.h>
#include <arpa/inet.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>

void pipeline_init(struct pipeline_ctx *ctx, struct syn_handler *sh,
                   struct translator *trans, struct eth1_io *eth1,
                   struct eth2_io *eth2, uint16_t app_port_base,
                   uint16_t app_port_count)
{
    ctx->sh             = sh;
    ctx->trans          = trans;
    ctx->eth1           = eth1;
    ctx->eth2           = eth2;
    ctx->app_port_base  = app_port_base;
    ctx->app_port_count = app_port_count ? app_port_count : 1;
}

/* True if the packet's src or dst port falls in [base, base+count). Ports in the
 * TCP header are network byte order; compare in host order. */
static inline int port_in_app_range(const struct pipeline_ctx *ctx,
                                    const struct rte_tcp_hdr *tcp)
{
    uint32_t lo = ctx->app_port_base;
    uint32_t hi = lo + ctx->app_port_count;          /* exclusive */
    uint16_t dp = rte_be_to_cpu_16(tcp->dst_port);
    uint16_t sp = rte_be_to_cpu_16(tcp->src_port);
    return (dp >= lo && dp < hi) || (sp >= lo && sp < hi);
}

/* ── eth1 ingress (DPDK mbuf from ClientNIC) ─────────────────────────────── */

void pipeline_feed_eth1(struct pipeline_ctx *ctx, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)data;

    /* Re-capture loop prevention */
    if (memcmp(eth->src_addr.addr_bytes, ctx->eth1->mac, 6) == 0)
        return;

    if (eth->ether_type != htons(RTE_ETHER_TYPE_IPV4))
        return;

    const struct rte_ipv4_hdr *ip = (const struct rte_ipv4_hdr *)(data + 14);
    if (ip->next_proto_id != IPPROTO_TCP)
        return;

    const struct rte_tcp_hdr *tcp = (const struct rte_tcp_hdr *)
                                    (data + 14 + ((ip->version_ihl & 0x0F) * 4));

    if (!port_in_app_range(ctx, tcp))
        return;

    uint8_t flags  = tcp->tcp_flags;
    int is_syn     = (flags & RTE_TCP_SYN_FLAG) && !(flags & RTE_TCP_ACK_FLAG);

    if (is_syn)
        syn_handler_handle_syn(ctx->sh, data, len);  /* extract V, zero ack, forward */
    else
        trans_c2s(ctx->trans, data, len);             /* subtract delta from ACK */
}

/* ── eth2 ingress (AF_PACKET raw buffer from Server) ────────────────────── */

void pipeline_feed_eth2(struct pipeline_ctx *ctx, uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)pkt;

    /* Re-capture loop prevention */
    if (memcmp(eth->src_addr.addr_bytes, ctx->eth2->mac, 6) == 0)
        return;

    if (eth->ether_type != htons(RTE_ETHER_TYPE_IPV4))
        return;

    const struct rte_ipv4_hdr *ip = (const struct rte_ipv4_hdr *)(pkt + 14);
    if (ip->next_proto_id != IPPROTO_TCP)
        return;

    const struct rte_tcp_hdr *tcp = (const struct rte_tcp_hdr *)
                                    (pkt + 14 + ((ip->version_ihl & 0x0F) * 4));

    if (!port_in_app_range(ctx, tcp))
        return;

    uint8_t flags     = tcp->tcp_flags;
    int is_syn_ack    = (flags & RTE_TCP_SYN_FLAG) && (flags & RTE_TCP_ACK_FLAG);

    /* For eth2, we receive raw buffers (AF_PACKET); wrap in a temporary mbuf-like
     * structure.  Since syn_handler_handle_syn_ack and trans_s2c both take rte_mbuf*,
     * we allocate a temporary mbuf to carry the packet.  The caller already provides
     * a raw buffer so we wrap it into a mbuf using the mempool. */

    /* Allocate a temporary mbuf from eth1's pool to pass to handlers */
    struct rte_mbuf *m = rte_pktmbuf_alloc(ctx->eth1->mbuf_pool);
    if (!m) {
        LOG_ERR("eth2 pipeline: mbuf alloc failed");
        return;
    }
    uint8_t *d = rte_pktmbuf_append(m, len);
    if (!d) {
        rte_pktmbuf_free(m);
        return;
    }
    memcpy(d, pkt, len);

    if (is_syn_ack)
        syn_handler_handle_syn_ack(ctx->sh, m);  /* compute delta, flush, DROP */
    else
        trans_s2c(ctx->trans, m);                /* add delta to SEQ, forward */

    rte_pktmbuf_free(m);
}
