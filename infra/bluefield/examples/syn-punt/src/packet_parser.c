/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#include "packet_parser.h"
#include "utils.h"
#include <stdio.h>
#include <string.h>
#include <rte_byteorder.h>

bool
parse_packet(struct rte_mbuf *pkt, struct packet_info *info)
{
    memset(info, 0, sizeof(*info));

    /* Parse Ethernet header */
    info->eth_hdr = rte_pktmbuf_mtod(pkt, struct rte_ether_hdr *);
    if (info->eth_hdr == NULL)
        return false;

    rte_ether_addr_copy(&info->eth_hdr->src_addr, &info->src_mac);
    rte_ether_addr_copy(&info->eth_hdr->dst_addr, &info->dst_mac);
    info->ether_type = rte_be_to_cpu_16(info->eth_hdr->ether_type);

    /* Check for IPv4 */
    if (info->ether_type != RTE_ETHER_TYPE_IPV4) {
        return true;  /* Valid packet, just not IPv4 */
    }

    /* Parse IPv4 header */
    info->ipv4_hdr = (struct rte_ipv4_hdr *)(info->eth_hdr + 1);
    info->is_ipv4 = true;
    info->src_ip = info->ipv4_hdr->src_addr;
    info->dst_ip = info->ipv4_hdr->dst_addr;
    info->protocol = info->ipv4_hdr->next_proto_id;

    /* Check for TCP */
    if (info->protocol != IPPROTO_TCP) {
        return true;  /* Valid IPv4, just not TCP */
    }

    /* Parse TCP header */
    uint8_t ipv4_hdr_len = (info->ipv4_hdr->version_ihl & 0x0F) * 4;
    info->tcp_hdr = (struct rte_tcp_hdr *)((uint8_t *)info->ipv4_hdr + ipv4_hdr_len);
    info->is_tcp = true;
    info->src_port = rte_be_to_cpu_16(info->tcp_hdr->src_port);
    info->dst_port = rte_be_to_cpu_16(info->tcp_hdr->dst_port);
    info->seq_num = rte_be_to_cpu_32(info->tcp_hdr->sent_seq);
    info->ack_num = rte_be_to_cpu_32(info->tcp_hdr->recv_ack);
    info->tcp_flags = info->tcp_hdr->tcp_flags;

    return true;
}

void
print_packet_info(const struct packet_info *info)
{
    char src_mac_str[32], dst_mac_str[32];
    char src_ip_str[32], dst_ip_str[32];

    format_mac_addr(&info->src_mac, src_mac_str, sizeof(src_mac_str));
    format_mac_addr(&info->dst_mac, dst_mac_str, sizeof(dst_mac_str));

    printf("=== SYN Packet Detected ===\n");
    printf("  ETH: %s -> %s\n", src_mac_str, dst_mac_str);

    if (info->is_ipv4) {
        format_ipv4_addr(info->src_ip, src_ip_str, sizeof(src_ip_str));
        format_ipv4_addr(info->dst_ip, dst_ip_str, sizeof(dst_ip_str));
        printf("  IP:  %s -> %s\n", src_ip_str, dst_ip_str);
    }

    if (info->is_tcp) {
        printf("  TCP: %u -> %u\n", info->src_port, info->dst_port);
        printf("  Seq: %u, Ack: %u\n", info->seq_num, info->ack_num);
        printf("  Flags: ");
        if (info->tcp_flags & RTE_TCP_SYN_FLAG) printf("SYN ");
        if (info->tcp_flags & RTE_TCP_ACK_FLAG) printf("ACK ");
        if (info->tcp_flags & RTE_TCP_FIN_FLAG) printf("FIN ");
        if (info->tcp_flags & RTE_TCP_RST_FLAG) printf("RST ");
        if (info->tcp_flags & RTE_TCP_PSH_FLAG) printf("PSH ");
        if (info->tcp_flags & RTE_TCP_URG_FLAG) printf("URG ");
        printf("\n");
    }

    printf("===========================\n");
}
