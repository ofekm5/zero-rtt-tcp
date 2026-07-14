#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <getopt.h>

#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "pipeline.h"
#include "log.h"

#define MBUF_POOL_SIZE  8191
#define MBUF_CACHE_SIZE 250
#define RX_BURST_SIZE   32

static volatile int running = 1;

static void signal_handler(int sig)
{
    (void)sig;
    running = 0;
}

static int parse_mac(const char *str, uint8_t *mac)
{
    unsigned int m[6];
    if (sscanf(str, "%x:%x:%x:%x:%x:%x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]) != 6)
        return -1;
    for (int i = 0; i < 6; i++)
        mac[i] = (uint8_t)m[i];
    return 0;
}

static void install_iptables(uint16_t base, uint16_t count)
{
    char cmd[256];
    uint16_t hi = (uint16_t)(base + (count ? count : 1) - 1);

    snprintf(cmd, sizeof(cmd),
             "iptables -A OUTPUT -p tcp --tcp-flags RST RST -j DROP");
    system(cmd);

    /* iptables accepts an inclusive port range with the lo:hi syntax */
    snprintf(cmd, sizeof(cmd),
             "iptables -A FORWARD -p tcp --dport %u:%u -j DROP", base, hi);
    system(cmd);

    snprintf(cmd, sizeof(cmd),
             "iptables -A FORWARD -p tcp --sport %u:%u -j DROP", base, hi);
    system(cmd);
}

int main(int argc, char *argv[])
{
    /* ── EAL init ────────────────────────────────────────────────────────── */
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        fprintf(stderr, "EAL init failed\n");
        return 1;
    }
    argc -= ret;
    argv += ret;

    log_init();

    /* ── CLI arg parsing (post-EAL) ──────────────────────────────────────── */
    uint16_t app_port = 8080;
    uint16_t app_port_count = 1;
    uint8_t  gw_mac[6]     = {0};  /* peer:  ClientNIC eth1 (next-hop) */
    uint8_t  server_mac[6] = {0};  /* peer:  Server eth0 (next-hop)    */
    int      gw_mac_set     = 0;
    int      server_mac_set = 0;
    uint8_t  client_port_mac[6] = {0};  /* local: our ClientNIC-facing ENI */
    uint8_t  server_port_mac[6] = {0};  /* local: our Server-facing ENI    */
    int      client_port_mac_set = 0;
    int      server_port_mac_set = 0;

    static struct option long_opts[] = {
        {"port",             required_argument, NULL, 'p'},
        {"port-count",       required_argument, NULL, 'n'},
        {"gw-mac",           required_argument, NULL, 'g'},
        {"server-mac",       required_argument, NULL, 'G'},
        {"client-port-mac",  required_argument, NULL, 'c'},
        {"server-port-mac",  required_argument, NULL, 's'},
        {NULL, 0, NULL, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "p:n:g:G:c:s:", long_opts, NULL)) != -1) {
        switch (opt) {
        case 'p':
            app_port = (uint16_t)atoi(optarg);
            break;
        case 'n':
            app_port_count = (uint16_t)atoi(optarg);
            if (app_port_count == 0)
                app_port_count = 1;
            break;
        case 'g':
            if (parse_mac(optarg, gw_mac) < 0) {
                LOG_ERR("Invalid --gw-mac: %s", optarg);
                return 1;
            }
            gw_mac_set = 1;
            break;
        case 'G':
            if (parse_mac(optarg, server_mac) < 0) {
                LOG_ERR("Invalid --server-mac: %s", optarg);
                return 1;
            }
            server_mac_set = 1;
            break;
        case 'c':
            if (parse_mac(optarg, client_port_mac) < 0) {
                LOG_ERR("Invalid --client-port-mac: %s", optarg);
                return 1;
            }
            client_port_mac_set = 1;
            break;
        case 's':
            if (parse_mac(optarg, server_port_mac) < 0) {
                LOG_ERR("Invalid --server-port-mac: %s", optarg);
                return 1;
            }
            server_port_mac_set = 1;
            break;
        default:
            fprintf(stderr,
                    "Usage: %s [EAL opts] -- --port=PORT [--port-count=N]"
                    " --gw-mac=CLIENTNIC_GW_MAC --server-mac=SERVER_MAC"
                    " --client-port-mac=MAC --server-port-mac=MAC\n", argv[0]);
            return 1;
        }
    }

    if (!gw_mac_set) {
        LOG_ERR("--gw-mac (ClientNIC-side gateway) is required");
        return 1;
    }
    if (!server_mac_set) {
        LOG_ERR("--server-mac (Server peer MAC) is required");
        return 1;
    }
    if (!client_port_mac_set) {
        LOG_ERR("--client-port-mac (our ClientNIC-facing ENI MAC) is required");
        return 1;
    }
    if (!server_port_mac_set) {
        LOG_ERR("--server-port-mac (our Server-facing ENI MAC) is required");
        return 1;
    }

    LOG_INFO("ServerNIC DPDK starting (port=%u..%u)",
             app_port, (uint16_t)(app_port + app_port_count - 1));

    /* ── Mempool ─────────────────────────────────────────────────────────── */
    struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL",
        MBUF_POOL_SIZE, MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
        rte_socket_id());
    if (!mbuf_pool) {
        LOG_ERR("Cannot create mbuf pool");
        return 1;
    }

    /* ── DPDK port check ─────────────────────────────────────────────────── */
    uint16_t nb_ports = rte_eth_dev_count_avail();
    if (nb_ports < 2) {
        LOG_ERR("Need 2 DPDK ports available (ClientNIC-facing + Server-facing),"
                " got %u (are both bound to vfio-pci?)", nb_ports);
        return 1;
    }

    /* ── Component init ──────────────────────────────────────────────────── */
    static struct eth1_io eth1;
    static struct eth2_io eth2;
    static struct flow_table ft;
    static struct syn_handler sh;
    static struct translator trans;
    static struct pipeline_ctx pipeline;

    /* Map roles to ports by MAC, never by port ID: DPDK numbers ports in PCI
     * order, which does not reliably follow ENI device_index, so a hardcoded
     * 0/1 split can silently swap the ClientNIC and Server links. */
    uint16_t client_port_id, server_port_id;
    if (io_find_port_by_mac(client_port_mac, &client_port_id) < 0) {
        LOG_ERR("No DPDK port with --client-port-mac "
                "%02x:%02x:%02x:%02x:%02x:%02x (is that ENI bound to vfio-pci?)",
                client_port_mac[0], client_port_mac[1], client_port_mac[2],
                client_port_mac[3], client_port_mac[4], client_port_mac[5]);
        return 1;
    }
    if (io_find_port_by_mac(server_port_mac, &server_port_id) < 0) {
        LOG_ERR("No DPDK port with --server-port-mac "
                "%02x:%02x:%02x:%02x:%02x:%02x (is that ENI bound to vfio-pci?)",
                server_port_mac[0], server_port_mac[1], server_port_mac[2],
                server_port_mac[3], server_port_mac[4], server_port_mac[5]);
        return 1;
    }
    if (client_port_id == server_port_id) {
        LOG_ERR("--client-port-mac and --server-port-mac resolve to the same "
                "DPDK port %u", client_port_id);
        return 1;
    }
    LOG_INFO("Port map: ClientNIC-facing=port %u, Server-facing=port %u",
             client_port_id, server_port_id);

    if (eth1_init(&eth1, client_port_id, mbuf_pool, gw_mac) < 0)
        return 1;
    if (eth2_init(&eth2, server_port_id, mbuf_pool, server_mac) < 0)
        return 1;

    ft_init(&ft);
    syn_handler_init(&sh, &ft, &eth1, &eth2);
    trans_init(&trans, &ft, &eth1, &eth2);
    pipeline_init(&pipeline, &sh, &trans, &eth1, &eth2, app_port, app_port_count);

    /* ── iptables rules ──────────────────────────────────────────────────── */
    install_iptables(app_port, app_port_count);

    /* ── Signal handler ──────────────────────────────────────────────────── */
    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    LOG_INFO("Entering busy-poll loop...");

    /* ── Main busy-poll loop ─────────────────────────────────────────────── */
    struct rte_mbuf *rx_bufs1[RX_BURST_SIZE];
    struct rte_mbuf *rx_bufs2[RX_BURST_SIZE];

    while (running) {
        /* Poll eth1 (DPDK rx_burst, from ClientNIC) */
        uint16_t nb_rx1 = rte_eth_rx_burst(eth1.port_id, 0, rx_bufs1, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx1; i++) {
            pipeline_feed_eth1(&pipeline, rx_bufs1[i]);
            rte_pktmbuf_free(rx_bufs1[i]);
        }

        /* Poll eth2 (DPDK rx_burst, from Server) */
        uint16_t nb_rx2 = rte_eth_rx_burst(eth2.port_id, 0, rx_bufs2, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx2; i++) {
            pipeline_feed_eth2(&pipeline, rx_bufs2[i]);
            rte_pktmbuf_free(rx_bufs2[i]);
        }
    }

    LOG_INFO("Shutting down...");
    rte_eth_dev_stop(eth1.port_id);
    rte_eth_dev_close(eth1.port_id);
    rte_eth_dev_stop(eth2.port_id);
    rte_eth_dev_close(eth2.port_id);
    rte_eal_cleanup();
    return 0;
}
