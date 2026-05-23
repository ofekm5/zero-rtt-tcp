/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#ifndef SYN_PUNT_PACKET_PARSER_H
#define SYN_PUNT_PACKET_PARSER_H

#include <stdint.h>
#include <stdbool.h>
#include <rte_mbuf.h>
#include <rte_ether.h>
#include <rte_ip.h>
#include <rte_tcp.h>

/**
 * Parsed packet information
 */
struct packet_info {
    /* Ethernet header */
    struct rte_ether_addr src_mac;
    struct rte_ether_addr dst_mac;
    uint16_t ether_type;

    /* IPv4 header (if present) */
    bool is_ipv4;
    uint32_t src_ip;
    uint32_t dst_ip;
    uint8_t protocol;

    /* TCP header (if present) */
    bool is_tcp;
    uint16_t src_port;
    uint16_t dst_port;
    uint32_t seq_num;
    uint32_t ack_num;
    uint8_t tcp_flags;

    /* Pointers to headers in mbuf */
    struct rte_ether_hdr *eth_hdr;
    struct rte_ipv4_hdr *ipv4_hdr;
    struct rte_tcp_hdr *tcp_hdr;
};

/**
 * Parse packet headers and extract information
 *
 * @param pkt Packet mbuf to parse
 * @param info Output packet information
 * @return true if packet was successfully parsed, false otherwise
 */
bool parse_packet(struct rte_mbuf *pkt, struct packet_info *info);

/**
 * Check if packet is a TCP SYN packet (SYN flag set, no ACK)
 *
 * @param info Parsed packet information
 * @return true if packet is a SYN packet
 */
static inline bool is_syn_packet(const struct packet_info *info)
{
    return info->is_tcp &&
           (info->tcp_flags & RTE_TCP_SYN_FLAG) &&
           !(info->tcp_flags & RTE_TCP_ACK_FLAG);
}

/**
 * Print packet information to stdout
 *
 * @param info Parsed packet information
 */
void print_packet_info(const struct packet_info *info);

#endif /* SYN_PUNT_PACKET_PARSER_H */
