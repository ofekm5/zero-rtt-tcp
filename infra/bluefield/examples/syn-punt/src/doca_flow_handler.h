/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#ifndef SYN_PUNT_DOCA_FLOW_HANDLER_H
#define SYN_PUNT_DOCA_FLOW_HANDLER_H

#include "utils.h"
#include <doca_error.h>

/**
 * Initialize DOCA Flow
 *
 * @param nb_queues Number of queues for flow processing
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t doca_flow_init_module(uint16_t nb_queues);

/**
 * Start DOCA Flow ports (both Port A and Port B)
 *
 * @param ctx DOCA Flow context to initialize
 * @param port_a_id DPDK port A ID (e.g., pf0hpf)
 * @param port_b_id DPDK port B ID (e.g., p0)
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t doca_flow_port_start_module(struct doca_flow_ctx *ctx, uint16_t port_a_id, uint16_t port_b_id);

/**
 * Create SYN punt hairpin pipes
 *
 * Creates pipes on both ports that:
 * - Match TCP SYN packets → Forward to RX queue 0 (exception path to ARM)
 * - Miss (non-SYN) → Forward to opposite port in HARDWARE (fast path, no ARM)
 *
 * This implements Option 1: Hardware hairpin without OVS
 *
 * @param ctx DOCA Flow context
 * @param port_a_id Port A ID
 * @param port_b_id Port B ID
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t create_syn_punt_pipe(struct doca_flow_ctx *ctx, uint16_t port_a_id, uint16_t port_b_id);

/**
 * Add SYN punt flow entry
 *
 * @param ctx DOCA Flow context
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t add_syn_punt_entry(struct doca_flow_ctx *ctx);

/**
 * Cleanup DOCA Flow resources
 *
 * @param ctx DOCA Flow context
 */
void doca_flow_cleanup(struct doca_flow_ctx *ctx);

#endif /* SYN_PUNT_DOCA_FLOW_HANDLER_H */
