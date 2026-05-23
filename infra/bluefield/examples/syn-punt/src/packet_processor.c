/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#include "packet_processor.h"
#include "packet_parser.h"
#include <doca_log.h>
#include <rte_ethdev.h>
#include <rte_cycles.h>

DOCA_LOG_REGISTER(PACKET_PROCESSOR);

#define STATS_INTERVAL_CYCLES (2 * rte_get_tsc_hz())  /* Print stats every 2 seconds */

doca_error_t
packet_processor_run(struct app_ctx *ctx)
{
    struct rte_mbuf *bufs[MAX_PKT_BURST];
    struct packet_info info;
    uint16_t nb_rx, nb_tx;
    uint16_t port_id = ctx->config.port_id;
    uint64_t last_stats_time = rte_get_tsc_cycles();
    uint64_t last_syn_count = 0;
    uint64_t last_total_count = 0;

    DOCA_LOG_INFO("Starting packet processor on port %u (queue 0)", port_id);
    DOCA_LOG_INFO("SYN packets will be printed to stdout and forwarded");
    DOCA_LOG_INFO("Non-SYN packets will be fast-forwarded via hardware");
    DOCA_LOG_INFO("Press Ctrl+C to quit\n");

    while (!ctx->config.force_quit) {
        /* Receive burst of packets from queue 0 (SYN packets punted by hardware) */
        nb_rx = rte_eth_rx_burst(port_id, 0, bufs, MAX_PKT_BURST);

        if (nb_rx == 0) {
            continue;
        }

        ctx->total_packets += nb_rx;

        /* Process each packet */
        for (uint16_t i = 0; i < nb_rx; i++) {
            struct rte_mbuf *pkt = bufs[i];

            /* Parse packet */
            if (!parse_packet(pkt, &info)) {
                /* Failed to parse, just forward */
                nb_tx = rte_eth_tx_burst(port_id, 0, &pkt, 1);
                if (nb_tx == 0) {
                    rte_pktmbuf_free(pkt);
                }
                continue;
            }

            /* Check if this is a SYN packet (should be, since hardware punted it) */
            if (is_syn_packet(&info)) {
                ctx->syn_packets++;

                /* Print SYN packet information to stdout */
                print_packet_info(&info);
            }

            /* Forward packet */
            nb_tx = rte_eth_tx_burst(port_id, 0, &pkt, 1);
            if (nb_tx == 0) {
                rte_pktmbuf_free(pkt);
                DOCA_LOG_WARN("Failed to forward packet");
            }
        }

        /* Print periodic statistics */
        uint64_t now = rte_get_tsc_cycles();
        if (now - last_stats_time > STATS_INTERVAL_CYCLES) {
            uint64_t syn_delta = ctx->syn_packets - last_syn_count;
            uint64_t total_delta = ctx->total_packets - last_total_count;

            DOCA_LOG_INFO("Statistics: Total=%lu (+%lu/2s), SYN=%lu (+%lu/2s)",
                         ctx->total_packets, total_delta,
                         ctx->syn_packets, syn_delta);

            last_stats_time = now;
            last_syn_count = ctx->syn_packets;
            last_total_count = ctx->total_packets;
        }
    }

    DOCA_LOG_INFO("\nPacket processor stopped");
    DOCA_LOG_INFO("Final statistics:");
    DOCA_LOG_INFO("  Total packets received: %lu", ctx->total_packets);
    DOCA_LOG_INFO("  SYN packets processed: %lu", ctx->syn_packets);
    DOCA_LOG_INFO("  Non-SYN packets (hardware fast-path): %lu",
                  ctx->total_packets - ctx->syn_packets);

    return DOCA_SUCCESS;
}
