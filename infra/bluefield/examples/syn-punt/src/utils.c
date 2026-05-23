/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#include "utils.h"
#include <string.h>
#include <stdio.h>
#include <arpa/inet.h>

void
app_ctx_init(struct app_ctx *ctx)
{
    memset(ctx, 0, sizeof(*ctx));

    /* Default configuration */
    ctx->config.port_a_id = 0;  /* Default: port 0 (e.g., pf0hpf) */
    ctx->config.port_b_id = 1;  /* Default: port 1 (e.g., p0) */
    ctx->config.nb_queues = 1;
    ctx->config.promiscuous_mode = true;
    ctx->config.timeout = 0;  /* Run indefinitely */
    ctx->config.force_quit = false;

    /* Initialize statistics */
    ctx->syn_packets = 0;
    ctx->total_packets = 0;
}

void
format_mac_addr(const struct rte_ether_addr *addr, char *buf, size_t buf_size)
{
    snprintf(buf, buf_size, "%02x:%02x:%02x:%02x:%02x:%02x",
             addr->addr_bytes[0], addr->addr_bytes[1],
             addr->addr_bytes[2], addr->addr_bytes[3],
             addr->addr_bytes[4], addr->addr_bytes[5]);
}

void
format_ipv4_addr(uint32_t ip, char *buf, size_t buf_size)
{
    struct in_addr addr;
    addr.s_addr = ip;
    snprintf(buf, buf_size, "%s", inet_ntoa(addr));
}
