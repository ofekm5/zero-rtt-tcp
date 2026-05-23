/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 *
 * DOCA Flow Handler - Option 1: Hairpin Forwarding Without OVS
 *
 * This implements bump-in-the-wire with hardware fast-path:
 * - Port A (pf0hpf) ←→ Port B (p0) forwarding in hardware
 * - SYN packets punted to software (queue 0)
 * - Non-SYN packets forwarded in hardware (never touch ARM cores)
 */

#include "doca_flow_handler.h"
#include <doca_log.h>
#include <doca_flow.h>
#include <rte_tcp.h>
#include <string.h>

DOCA_LOG_REGISTER(DOCA_FLOW);

#define DEFAULT_TIMEOUT_US 10000  /* 10ms timeout for entry processing */

doca_error_t
doca_flow_init_module(uint16_t nb_queues)
{
    struct doca_flow_cfg flow_cfg = {0};
    doca_error_t result;

    flow_cfg.pipe_queues = nb_queues;
    flow_cfg.mode_args = "vnf,hws";  /* VNF mode with hardware steering */
    flow_cfg.resource.nb_counters = 1024;

    result = doca_flow_init(&flow_cfg);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to initialize DOCA Flow: %s",
                     doca_error_get_descr(result));
        return result;
    }

    DOCA_LOG_INFO("DOCA Flow initialized (mode: %s, queues: %u)",
                  flow_cfg.mode_args, nb_queues);
    return DOCA_SUCCESS;
}

doca_error_t
doca_flow_port_start_module(struct doca_flow_ctx *ctx, uint16_t port_a_id, uint16_t port_b_id)
{
    struct doca_flow_port_cfg port_cfg = {0};
    doca_error_t result;

    /* Start Port A */
    port_cfg.port_id = port_a_id;
    port_cfg.type = DOCA_FLOW_PORT_DPDK_BY_ID;

    result = doca_flow_port_start(&port_cfg, &ctx->port_a);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to start DOCA Flow port A (%u): %s",
                     port_a_id, doca_error_get_descr(result));
        return result;
    }

    DOCA_LOG_INFO("DOCA Flow port A (%u) started", port_a_id);

    /* Start Port B */
    port_cfg.port_id = port_b_id;
    port_cfg.type = DOCA_FLOW_PORT_DPDK_BY_ID;

    result = doca_flow_port_start(&port_cfg, &ctx->port_b);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to start DOCA Flow port B (%u): %s",
                     port_b_id, doca_error_get_descr(result));
        return result;
    }

    DOCA_LOG_INFO("DOCA Flow port B (%u) started", port_b_id);

    return DOCA_SUCCESS;
}

/**
 * Create a pipe for SYN punt with hardware hairpin forwarding
 *
 * @param port DOCA Flow port
 * @param opposite_port_id Opposite port ID for hairpin forwarding
 * @param pipe Output pipe
 * @return DOCA_SUCCESS on success
 */
static doca_error_t
create_hairpin_pipe(struct doca_flow_port *port, uint16_t opposite_port_id,
                    struct doca_flow_pipe **pipe, const char *pipe_name)
{
    struct doca_flow_match match = {0};
    struct doca_flow_fwd fwd_syn = {0};
    struct doca_flow_fwd fwd_miss = {0};
    struct doca_flow_pipe_cfg pipe_cfg = {0};
    doca_error_t result;

    /* Match on TCP packets */
    match.parser_meta.outer_l3_type = DOCA_FLOW_L3_META_IPV4;
    match.parser_meta.outer_l4_type = DOCA_FLOW_L4_META_TCP;
    match.outer.l3_type = DOCA_FLOW_L3_TYPE_IP4;
    match.outer.l4_type_ext = DOCA_FLOW_L4_TYPE_EXT_TCP;

    /* Match TCP SYN flag */
    match.outer.tcp.flags = RTE_TCP_SYN_FLAG;

    /*
     * SYN packets: Forward to queue 0 (exception path to ARM cores)
     */
    fwd_syn.type = DOCA_FLOW_FWD_RSS;
    fwd_syn.rss_queues = (uint16_t[]){0};
    fwd_syn.num_of_queues = 1;

    /*
     * Non-SYN packets: Forward to opposite port in HARDWARE (fast path)
     * This is the critical part for Option 1!
     */
    fwd_miss.type = DOCA_FLOW_FWD_PORT;
    fwd_miss.port_id = opposite_port_id;

    /* Configure pipe */
    pipe_cfg.attr.name = pipe_name;
    pipe_cfg.attr.type = DOCA_FLOW_PIPE_BASIC;
    pipe_cfg.attr.is_root = true;
    pipe_cfg.attr.enable_strict_matching = false;
    pipe_cfg.match = &match;
    pipe_cfg.port = port;

    result = doca_flow_pipe_create(&pipe_cfg, &fwd_syn, &fwd_miss, pipe);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to create pipe '%s': %s",
                     pipe_name, doca_error_get_descr(result));
        return result;
    }

    DOCA_LOG_INFO("Created pipe '%s':", pipe_name);
    DOCA_LOG_INFO("  - SYN packets → Queue 0 (ARM cores)");
    DOCA_LOG_INFO("  - Non-SYN packets → Port %u (hardware fast-path)", opposite_port_id);

    return DOCA_SUCCESS;
}

doca_error_t
create_syn_punt_pipe(struct doca_flow_ctx *ctx, uint16_t port_a_id, uint16_t port_b_id)
{
    doca_error_t result;

    /*
     * Create Pipe A: Port A → Port B hairpin
     * SYN → Queue 0, Non-SYN → Port B (hardware)
     */
    result = create_hairpin_pipe(ctx->port_a, port_b_id, &ctx->pipe_a,
                                  "PORT_A_HAIRPIN");
    if (result != DOCA_SUCCESS) {
        return result;
    }

    /*
     * Create Pipe B: Port B → Port A hairpin
     * SYN → Queue 0, Non-SYN → Port A (hardware)
     */
    result = create_hairpin_pipe(ctx->port_b, port_a_id, &ctx->pipe_b,
                                  "PORT_B_HAIRPIN");
    if (result != DOCA_SUCCESS) {
        return result;
    }

    DOCA_LOG_INFO("\n=== Hairpin Configuration Complete ===");
    DOCA_LOG_INFO("Port A (ID %u) ←[hardware]→ Port B (ID %u)", port_a_id, port_b_id);
    DOCA_LOG_INFO("SYN packets on either port → ARM cores (queue 0)");
    DOCA_LOG_INFO("Non-SYN packets → Hardware forwarding (NO ARM!)");
    DOCA_LOG_INFO("=====================================\n");

    return DOCA_SUCCESS;
}

doca_error_t
add_syn_punt_entry(struct doca_flow_ctx *ctx)
{
    struct doca_flow_match match = {0};
    struct doca_flow_fwd fwd = {0};
    doca_error_t result;

    /* Match TCP SYN packets */
    match.outer.tcp.flags = RTE_TCP_SYN_FLAG;

    /* Forward to queue 0 */
    fwd.type = DOCA_FLOW_FWD_RSS;
    fwd.rss_queues = (uint16_t[]){0};
    fwd.num_of_queues = 1;

    /* Add entry to Pipe A */
    result = doca_flow_pipe_add_entry(
        0,                  /* Queue ID */
        ctx->pipe_a,
        &match,
        NULL,               /* Actions */
        NULL,               /* Monitor */
        &fwd,
        0,                  /* Flags */
        NULL,               /* User context */
        &ctx->entry_a
    );

    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to add entry to Pipe A: %s",
                     doca_error_get_descr(result));
        return result;
    }

    /* Add entry to Pipe B */
    result = doca_flow_pipe_add_entry(
        0,                  /* Queue ID */
        ctx->pipe_b,
        &match,
        NULL,               /* Actions */
        NULL,               /* Monitor */
        &fwd,
        0,                  /* Flags */
        NULL,               /* User context */
        &ctx->entry_b
    );

    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to add entry to Pipe B: %s",
                     doca_error_get_descr(result));
        return result;
    }

    /* Process entries to commit to hardware */
    result = doca_flow_entries_process(ctx->port_a, 0, DEFAULT_TIMEOUT_US, 0);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_WARN("Failed to process entries for Port A: %s",
                      doca_error_get_descr(result));
    }

    result = doca_flow_entries_process(ctx->port_b, 0, DEFAULT_TIMEOUT_US, 0);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_WARN("Failed to process entries for Port B: %s",
                      doca_error_get_descr(result));
    }

    DOCA_LOG_INFO("SYN punt entries added and committed to hardware");
    return DOCA_SUCCESS;
}

void
doca_flow_cleanup(struct doca_flow_ctx *ctx)
{
    /* Remove entries */
    if (ctx->entry_a) {
        doca_flow_pipe_rm_entry(0, ctx->entry_a);
        DOCA_LOG_INFO("Removed entry from Pipe A");
    }

    if (ctx->entry_b) {
        doca_flow_pipe_rm_entry(0, ctx->entry_b);
        DOCA_LOG_INFO("Removed entry from Pipe B");
    }

    /* Destroy pipes */
    if (ctx->pipe_a) {
        doca_flow_pipe_destroy(ctx->pipe_a);
        DOCA_LOG_INFO("Destroyed Pipe A");
    }

    if (ctx->pipe_b) {
        doca_flow_pipe_destroy(ctx->pipe_b);
        DOCA_LOG_INFO("Destroyed Pipe B");
    }

    /* Stop ports */
    if (ctx->port_a) {
        doca_flow_port_stop(ctx->port_a);
        DOCA_LOG_INFO("Stopped DOCA Flow port A");
    }

    if (ctx->port_b) {
        doca_flow_port_stop(ctx->port_b);
        DOCA_LOG_INFO("Stopped DOCA Flow port B");
    }

    doca_flow_destroy();
    DOCA_LOG_INFO("DOCA Flow destroyed");
}
