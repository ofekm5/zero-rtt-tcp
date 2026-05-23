/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#ifndef SYN_PUNT_DPDK_INIT_H
#define SYN_PUNT_DPDK_INIT_H

#include "utils.h"
#include <doca_error.h>

/**
 * Initialize DPDK EAL (Environment Abstraction Layer)
 *
 * @param argc Pointer to argument count
 * @param argv Pointer to argument vector
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t dpdk_init_eal(int *argc, char ***argv);

/**
 * Initialize DPDK port with RX/TX queues
 *
 * @param ctx DPDK port context to initialize
 * @param port_id Port ID to initialize
 * @param nb_queues Number of RX/TX queues
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t dpdk_port_init(struct dpdk_port_ctx *ctx, uint16_t port_id, uint16_t nb_queues);

/**
 * Enable promiscuous mode on port
 *
 * @param port_id Port ID
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t dpdk_port_set_promiscuous(uint16_t port_id);

/**
 * Cleanup DPDK resources
 *
 * @param ctx DPDK port context
 */
void dpdk_cleanup(struct dpdk_port_ctx *ctx);

#endif /* SYN_PUNT_DPDK_INIT_H */
