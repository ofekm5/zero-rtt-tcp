#include "pipeline.h"
#include "log.h"

#include <string.h>
#include <arpa/inet.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>

void pipeline_init(struct pipeline_ctx *ctx, struct packet_processor *proc,
                   struct forwarder *fwd, struct eth0_io *eth0,
                   struct eth1_io *eth1, uint16_t app_port)
{
    ctx->proc     = proc;
    ctx->fwd      = fwd;
    ctx->eth0     = eth0;
    ctx->eth1     = eth1;
    ctx->app_port = htons(app_port);
}

/* ── eth0 ingress (AF_PACKET raw buffer from client) ─────────────────────── */

void pipeline_feed_eth0(struct pipeline_ctx *ctx, uint8_t *pkt, uint16_t len)
{
    if (len < 54)
        return;

    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)pkt;

    /* Drop our own re-captured packets */
    if (memcmp(eth->src_addr.addr_bytes, ctx->eth0->mac, 6) == 0)
        return;

    if (eth->ether_type != htons(RTE_ETHER_TYPE_IPV4))
        return;

    const struct rte_ipv4_hdr *ip = (const struct rte_ipv4_hdr *)(pkt + 14);
    if (ip->next_proto_id != IPPROTO_TCP)
        return;

    const struct rte_tcp_hdr *tcp = (const struct rte_tcp_hdr *)
                                    (pkt + 14 + ((ip->version_ihl & 0x0F) * 4));

    if (tcp->dst_port != ctx->app_port && tcp->src_port != ctx->app_port)
        return;

    uint8_t flags  = tcp->tcp_flags;
    int is_syn     = (flags & RTE_TCP_SYN_FLAG) && !(flags & RTE_TCP_ACK_FLAG);

    if (is_syn)
        proc_handle_syn(ctx->proc, pkt, len);  /* spoof SYN-ACK + forward SYN with V */
    else
        forward_c2s(ctx->fwd, pkt, len);        /* transparent forward, no seq/ack change */
}

/* ── eth1 ingress (DPDK mbuf from ServerNIC/server side) ────────────────── */

void pipeline_feed_eth1(struct pipeline_ctx *ctx, struct rte_mbuf *mbuf)
{
    uint8_t *data = rte_pktmbuf_mtod(mbuf, uint8_t *);
    uint16_t len  = rte_pktmbuf_data_len(mbuf);

    if (len < 54)
        return;

    const struct rte_ether_hdr *eth = (const struct rte_ether_hdr *)data;

    if (memcmp(eth->src_addr.addr_bytes, ctx->eth1->mac, 6) == 0)
        return;

    if (eth->ether_type != htons(RTE_ETHER_TYPE_IPV4))
        return;

    const struct rte_ipv4_hdr *ip = (const struct rte_ipv4_hdr *)(data + 14);
    if (ip->next_proto_id != IPPROTO_TCP)
        return;

    const struct rte_tcp_hdr *tcp = (const struct rte_tcp_hdr *)
                                    (data + 14 + ((ip->version_ihl & 0x0F) * 4));

    if (tcp->dst_port != ctx->app_port && tcp->src_port != ctx->app_port)
        return;

    /* All eth1 traffic is forwarded transparently: the real SYN-ACK is dropped
     * at the ServerNIC and never reaches us.  No special-case for SYN-ACK. */
    forward_s2c(ctx->fwd, mbuf);
}
