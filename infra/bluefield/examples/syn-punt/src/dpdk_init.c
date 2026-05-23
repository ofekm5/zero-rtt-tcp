/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 */

#include "dpdk_init.h"
#include <doca_log.h>
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

DOCA_LOG_REGISTER(DPDK_INIT);

doca_error_t
dpdk_init_eal(int *argc, char ***argv)
{
    int ret;

    ret = rte_eal_init(*argc, *argv);
    if (ret < 0) {
        DOCA_LOG_ERR("Failed to initialize DPDK EAL: %s", rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    /* Update argc/argv to skip EAL arguments */
    *argc -= ret;
    *argv += ret;

    DOCA_LOG_INFO("DPDK EAL initialized successfully");
    return DOCA_SUCCESS;
}

doca_error_t
dpdk_port_init(struct dpdk_port_ctx *ctx, uint16_t port_id, uint16_t nb_queues)
{
    struct rte_eth_conf port_conf = {0};
    struct rte_eth_dev_info dev_info;
    struct rte_eth_rxconf rxq_conf;
    struct rte_eth_txconf txq_conf;
    char pool_name[32];
    int ret;
    uint16_t q;

    ctx->port_id = port_id;
    ctx->nb_rxd = RING_SIZE;
    ctx->nb_txd = RING_SIZE;

    /* Validate port */
    if (!rte_eth_dev_is_valid_port(port_id)) {
        DOCA_LOG_ERR("Port %u is not valid", port_id);
        return DOCA_ERROR_INVALID_VALUE;
    }

    /* Get device info */
    ret = rte_eth_dev_info_get(port_id, &dev_info);
    if (ret != 0) {
        DOCA_LOG_ERR("Failed to get device info for port %u: %s",
                     port_id, rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    DOCA_LOG_INFO("Initializing port %u (%s)", port_id,
                  dev_info.driver_name ? dev_info.driver_name : "unknown");

    /* Create mbuf pool */
    snprintf(pool_name, sizeof(pool_name), "MBUF_POOL_%u", port_id);
    ctx->mbuf_pool = rte_pktmbuf_pool_create(
        pool_name,
        NUM_MBUFS,
        MBUF_CACHE_SIZE,
        0,
        RTE_MBUF_DEFAULT_BUF_SIZE,
        rte_socket_id()
    );

    if (ctx->mbuf_pool == NULL) {
        DOCA_LOG_ERR("Failed to create mbuf pool for port %u", port_id);
        return DOCA_ERROR_NO_MEMORY;
    }

    /* Configure device */
    ret = rte_eth_dev_configure(port_id, nb_queues, nb_queues, &port_conf);
    if (ret != 0) {
        DOCA_LOG_ERR("Failed to configure port %u: %s", port_id, rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    /* Adjust ring sizes */
    ret = rte_eth_dev_adjust_nb_rx_tx_desc(port_id, &ctx->nb_rxd, &ctx->nb_txd);
    if (ret != 0) {
        DOCA_LOG_ERR("Failed to adjust descriptors for port %u: %s",
                     port_id, rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    /* Setup RX queues */
    rxq_conf = dev_info.default_rxconf;
    rxq_conf.offloads = port_conf.rxmode.offloads;

    for (q = 0; q < nb_queues; q++) {
        ret = rte_eth_rx_queue_setup(
            port_id,
            q,
            ctx->nb_rxd,
            rte_eth_dev_socket_id(port_id),
            &rxq_conf,
            ctx->mbuf_pool
        );

        if (ret < 0) {
            DOCA_LOG_ERR("Failed to setup RX queue %u on port %u: %s",
                         q, port_id, rte_strerror(-ret));
            return DOCA_ERROR_DRIVER;
        }
    }

    /* Setup TX queues */
    txq_conf = dev_info.default_txconf;
    txq_conf.offloads = port_conf.txmode.offloads;

    for (q = 0; q < nb_queues; q++) {
        ret = rte_eth_tx_queue_setup(
            port_id,
            q,
            ctx->nb_txd,
            rte_eth_dev_socket_id(port_id),
            &txq_conf
        );

        if (ret < 0) {
            DOCA_LOG_ERR("Failed to setup TX queue %u on port %u: %s",
                         q, port_id, rte_strerror(-ret));
            return DOCA_ERROR_DRIVER;
        }
    }

    /* Start device */
    ret = rte_eth_dev_start(port_id);
    if (ret < 0) {
        DOCA_LOG_ERR("Failed to start port %u: %s", port_id, rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    /* Get and display MAC address */
    struct rte_ether_addr addr;
    ret = rte_eth_macaddr_get(port_id, &addr);
    if (ret == 0) {
        char mac_str[32];
        format_mac_addr(&addr, mac_str, sizeof(mac_str));
        DOCA_LOG_INFO("Port %u MAC: %s", port_id, mac_str);
    }

    DOCA_LOG_INFO("Port %u initialized with %u queues (RXD=%u, TXD=%u)",
                  port_id, nb_queues, ctx->nb_rxd, ctx->nb_txd);

    return DOCA_SUCCESS;
}

doca_error_t
dpdk_port_set_promiscuous(uint16_t port_id)
{
    int ret;

    ret = rte_eth_promiscuous_enable(port_id);
    if (ret != 0) {
        DOCA_LOG_ERR("Failed to enable promiscuous mode on port %u: %s",
                     port_id, rte_strerror(-ret));
        return DOCA_ERROR_DRIVER;
    }

    DOCA_LOG_INFO("Promiscuous mode enabled on port %u", port_id);
    return DOCA_SUCCESS;
}

void
dpdk_cleanup(struct dpdk_port_ctx *ctx)
{
    if (ctx->port_id != UINT16_MAX) {
        rte_eth_dev_stop(ctx->port_id);
        rte_eth_dev_close(ctx->port_id);
        DOCA_LOG_INFO("Closed port %u", ctx->port_id);
    }

    /* Note: mbuf_pool is freed by rte_eal_cleanup() */
}
