/*
 * Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES, ALL RIGHTS RESERVED.
 *
 * SYN Punt Application
 *
 * This application demonstrates DOCA Flow hardware offload for selective
 * packet processing:
 * - TCP SYN packets are punted to the application (exception path)
 * - All other packets are forwarded in hardware (fast path)
 * - SYN packets are printed to stdout and then forwarded
 */

#include "utils.h"
#include "dpdk_init.h"
#include "doca_flow_handler.h"
#include "packet_processor.h"

#include <doca_log.h>
#include <doca_argp.h>
#include <signal.h>
#include <unistd.h>

DOCA_LOG_REGISTER(SYN_PUNT_MAIN);

/* Global application context for signal handler */
static struct app_ctx *global_ctx = NULL;

/**
 * Signal handler for graceful shutdown
 */
static void
signal_handler(int signum)
{
    if (signum == SIGINT || signum == SIGTERM) {
        DOCA_LOG_INFO("\nSignal %d received, shutting down...", signum);
        if (global_ctx) {
            global_ctx->config.force_quit = true;
        }
    }
}

/**
 * Cleanup all resources
 */
static void
cleanup(struct app_ctx *ctx)
{
    DOCA_LOG_INFO("Cleaning up resources...");

    /* Cleanup DOCA Flow */
    doca_flow_cleanup(&ctx->doca_ctx);

    /* Cleanup DPDK */
    dpdk_cleanup(&ctx->dpdk_ctx);

    /* Cleanup DPDK EAL */
    rte_eal_cleanup();

    DOCA_LOG_INFO("Cleanup complete");
}

/**
 * Callback for port argument
 */
static doca_error_t
port_callback(void *param, void *config)
{
    struct syn_punt_config *cfg = (struct syn_punt_config *)config;
    int port = *(int *)param;

    if (port < 0 || port > UINT16_MAX) {
        DOCA_LOG_ERR("Invalid port ID: %d", port);
        return DOCA_ERROR_INVALID_VALUE;
    }

    cfg->port_id = (uint16_t)port;
    return DOCA_SUCCESS;
}

/**
 * Callback for timeout argument
 */
static doca_error_t
timeout_callback(void *param, void *config)
{
    struct syn_punt_config *cfg = (struct syn_punt_config *)config;
    int timeout = *(int *)param;

    if (timeout < 0) {
        DOCA_LOG_ERR("Invalid timeout: %d", timeout);
        return DOCA_ERROR_INVALID_VALUE;
    }

    cfg->timeout = timeout;
    return DOCA_SUCCESS;
}

/**
 * Register application arguments
 */
static doca_error_t
register_app_params(void)
{
    doca_error_t result;

    struct doca_argp_param *port_param;
    result = doca_argp_param_create(&port_param);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to create port parameter");
        return result;
    }

    doca_argp_param_set_short_name(port_param, "p");
    doca_argp_param_set_long_name(port_param, "port");
    doca_argp_param_set_description(port_param, "DPDK port ID to use (default: 0)");
    doca_argp_param_set_callback(port_param, port_callback);
    doca_argp_param_set_type(port_param, DOCA_ARGP_TYPE_INT);

    result = doca_argp_register_param(port_param);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to register port parameter");
        return result;
    }

    struct doca_argp_param *timeout_param;
    result = doca_argp_param_create(&timeout_param);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to create timeout parameter");
        return result;
    }

    doca_argp_param_set_short_name(timeout_param, "t");
    doca_argp_param_set_long_name(timeout_param, "timeout");
    doca_argp_param_set_description(timeout_param, "Timeout in seconds (0 = infinite, default: 0)");
    doca_argp_param_set_callback(timeout_param, timeout_callback);
    doca_argp_param_set_type(timeout_param, DOCA_ARGP_TYPE_INT);

    result = doca_argp_register_param(timeout_param);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to register timeout parameter");
        return result;
    }

    return DOCA_SUCCESS;
}

/**
 * Main entry point
 */
int
main(int argc, char **argv)
{
    struct app_ctx ctx;
    doca_error_t result;
    int exit_status = EXIT_SUCCESS;

    /* Initialize application context */
    app_ctx_init(&ctx);
    global_ctx = &ctx;

    /* Setup signal handlers */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* Initialize DOCA argument parser */
    result = doca_argp_init("syn_punt", &ctx.config);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to initialize DOCA argument parser: %s",
                     doca_error_get_descr(result));
        return EXIT_FAILURE;
    }

    /* Register application parameters */
    result = register_app_params();
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to register application parameters");
        doca_argp_destroy();
        return EXIT_FAILURE;
    }

    /* Parse arguments */
    result = doca_argp_start(argc, argv);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to parse arguments: %s",
                     doca_error_get_descr(result));
        doca_argp_destroy();
        return EXIT_FAILURE;
    }

    DOCA_LOG_INFO("=== SYN Punt Application ===");
    DOCA_LOG_INFO("Port: %u", ctx.config.port_id);
    DOCA_LOG_INFO("Timeout: %s", ctx.config.timeout == 0 ? "infinite" : "limited");
    DOCA_LOG_INFO("============================\n");

    /* Initialize DPDK EAL */
    result = dpdk_init_eal(&argc, &argv);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to initialize DPDK EAL");
        exit_status = EXIT_FAILURE;
        goto cleanup_argp;
    }

    /* Initialize DPDK port */
    result = dpdk_port_init(&ctx.dpdk_ctx, ctx.config.port_id, ctx.config.nb_queues);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to initialize DPDK port");
        exit_status = EXIT_FAILURE;
        goto cleanup_dpdk;
    }

    /* Enable promiscuous mode if configured */
    if (ctx.config.promiscuous_mode) {
        result = dpdk_port_set_promiscuous(ctx.config.port_id);
        if (result != DOCA_SUCCESS) {
            DOCA_LOG_WARN("Failed to enable promiscuous mode");
        }
    }

    /* Initialize DOCA Flow */
    result = doca_flow_init_module(ctx.config.nb_queues);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to initialize DOCA Flow");
        exit_status = EXIT_FAILURE;
        goto cleanup_dpdk;
    }

    /* Start DOCA Flow port */
    result = doca_flow_port_start_module(&ctx.doca_ctx, ctx.config.port_id);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to start DOCA Flow port");
        exit_status = EXIT_FAILURE;
        goto cleanup_doca_flow;
    }

    /* Create SYN punt pipeline */
    result = create_syn_punt_pipe(&ctx.doca_ctx);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to create SYN punt pipe");
        exit_status = EXIT_FAILURE;
        goto cleanup_doca_flow;
    }

    /* Add SYN punt entry */
    result = add_syn_punt_entry(&ctx.doca_ctx);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Failed to add SYN punt entry");
        exit_status = EXIT_FAILURE;
        goto cleanup_doca_flow;
    }

    DOCA_LOG_INFO("\n=== Initialization Complete ===");
    DOCA_LOG_INFO("Hardware is configured to:");
    DOCA_LOG_INFO("  - Punt TCP SYN packets to RX queue 0");
    DOCA_LOG_INFO("  - Fast-forward all other packets");
    DOCA_LOG_INFO("================================\n");

    /* Run packet processor */
    result = packet_processor_run(&ctx);
    if (result != DOCA_SUCCESS) {
        DOCA_LOG_ERR("Packet processor failed: %s",
                     doca_error_get_descr(result));
        exit_status = EXIT_FAILURE;
    }

    /* Cleanup and exit */
cleanup_doca_flow:
    doca_flow_cleanup(&ctx.doca_ctx);

cleanup_dpdk:
    dpdk_cleanup(&ctx.dpdk_ctx);
    rte_eal_cleanup();

cleanup_argp:
    doca_argp_destroy();

    DOCA_LOG_INFO("Application terminated");
    return exit_status;
}
