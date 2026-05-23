/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#ifndef SYN_PUNT_PACKET_PROCESSOR_H
#define SYN_PUNT_PACKET_PROCESSOR_H

#include "utils.h"
#include <doca_error.h>

/**
 * Main packet processing loop
 *
 * Continuously receives packets from RX queue 0, processes SYN packets,
 * and forwards all packets.
 *
 * @param ctx Application context
 * @return DOCA_SUCCESS on success, error code otherwise
 */
doca_error_t packet_processor_run(struct app_ctx *ctx);

#endif /* SYN_PUNT_PACKET_PROCESSOR_H */
