/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 *
 * This software product is a proprietary product of NVIDIA CORPORATION &
 * AFFILIATES (the "Company") and all right, title, and interest in and to the
 * software product, including all associated intellectual property rights, are
 * and shall remain exclusively with the Company.
 */

#ifndef SYN_PUNT_UTILS_H
#define SYN_PUNT_UTILS_H

#include <stdint.h>
#include <stdbool.h>
#include <doca_flow.h>
#include <rte_mbuf.h>

/* Maximum packet burst size */
#define MAX_PKT_BURST 32

/* DPDK memory configuration */
#define RING_SIZE 1024
#define NUM_MBUFS 8192
#define MBUF_CACHE_SIZE 250

/**
 * Application configuration structure
 */
struct syn_punt_config {
    uint16_t port_a_id;            /* DPDK port A ID (e.g., pf0hpf) */
    uint16_t port_b_id;            /* DPDK port B ID (e.g., p0) */
    uint16_t nb_queues;            /* Number of RX/TX queues */
    bool promiscuous_mode;         /* Enable promiscuous mode */
    int timeout;                   /* Timeout in seconds (0 = infinite) */
    volatile bool force_quit;      /* Signal to quit application */
};

/**
 * DPDK port context
 */
struct dpdk_port_ctx {
    uint16_t port_a_id;
    uint16_t port_b_id;
    struct rte_mempool *mbuf_pool_a;
    struct rte_mempool *mbuf_pool_b;
    uint16_t nb_rxd;
    uint16_t nb_txd;
};

/**
 * DOCA Flow context
 */
struct doca_flow_ctx {
    struct doca_flow_port *port_a;      /* Port A (e.g., pf0hpf) */
    struct doca_flow_port *port_b;      /* Port B (e.g., p0) */
    struct doca_flow_pipe *pipe_a;      /* Pipe on port A */
    struct doca_flow_pipe *pipe_b;      /* Pipe on port B */
    struct doca_flow_pipe_entry *entry_a;  /* Entry on port A */
    struct doca_flow_pipe_entry *entry_b;  /* Entry on port B */
};

/**
 * Global application context
 */
struct app_ctx {
    struct syn_punt_config config;
    struct dpdk_port_ctx dpdk_ctx;
    struct doca_flow_ctx doca_ctx;
    uint64_t syn_packets;          /* Statistics */
    uint64_t total_packets;
};

/**
 * Initialize application context with default values
 *
 * @param ctx Application context to initialize
 */
void app_ctx_init(struct app_ctx *ctx);

/**
 * Format MAC address as string
 *
 * @param addr MAC address
 * @param buf Buffer to write string
 * @param buf_size Size of buffer
 */
void format_mac_addr(const struct rte_ether_addr *addr, char *buf, size_t buf_size);

/**
 * Format IPv4 address as string
 *
 * @param ip IPv4 address in network byte order
 * @param buf Buffer to write string
 * @param buf_size Size of buffer
 */
void format_ipv4_addr(uint32_t ip, char *buf, size_t buf_size);

#endif /* SYN_PUNT_UTILS_H */
