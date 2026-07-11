#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <getopt.h>

#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include "pipeline.h"
#include "capture.h"
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
    int ret = rte_eal_init(argc, argv);
    if (ret < 0) {
        fprintf(stderr, "EAL init failed\n");
        return 1;
    }
    argc -= ret;
    argv += ret;

    log_init();

    uint16_t app_port = 8080;
    uint16_t app_port_count = 1;
    uint8_t  gw_mac[6] = {0};
    int      gw_mac_set = 0;
    uint8_t  client_mac[6] = {0};
    int      client_mac_set = 0;
    const char *server_pcap_path = NULL;

    static struct option long_opts[] = {
        {"port",           required_argument, NULL, 'p'},
        {"port-count",     required_argument, NULL, 'n'},
        {"gw-mac",         required_argument, NULL, 'g'},
        {"client-mac",     required_argument, NULL, 'm'},
        {"server-pcap",    required_argument, NULL, 'w'},
        {NULL, 0, NULL, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "p:n:g:m:w:", long_opts, NULL)) != -1) {
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
        case 'm':
            if (parse_mac(optarg, client_mac) < 0) {
                LOG_ERR("Invalid --client-mac: %s", optarg);
                return 1;
            }
            client_mac_set = 1;
            break;
        case 'w':
            server_pcap_path = optarg;
            break;
        default:
            fprintf(stderr,
                    "Usage: %s [EAL opts] -- --port=PORT [--port-count=N]"
                    " --gw-mac=MAC --client-mac=MAC [--server-pcap=FILE]\n", argv[0]);
            return 1;
        }
    }

    if (!gw_mac_set) {
        LOG_ERR("--gw-mac is required");
        return 1;
    }
    if (!client_mac_set) {
        LOG_ERR("--client-mac is required");
        return 1;
    }

    LOG_INFO("ClientNIC DPDK Forwarder starting (port=%u..%u)",
             app_port, (uint16_t)(app_port + app_port_count - 1));
    LOG_INFO("Gateway MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             gw_mac[0], gw_mac[1], gw_mac[2],
             gw_mac[3], gw_mac[4], gw_mac[5]);
    LOG_INFO("Client MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             client_mac[0], client_mac[1], client_mac[2],
             client_mac[3], client_mac[4], client_mac[5]);

    struct rte_mempool *mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL",
        MBUF_POOL_SIZE, MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
        rte_socket_id());
    if (!mbuf_pool) {
        LOG_ERR("Cannot create mbuf pool");
        return 1;
    }

    uint16_t nb_ports = rte_eth_dev_count_avail();
    if (nb_ports < 2) {
        LOG_ERR("Need 2 DPDK ports available (client + server), got %u"
                " (are both bound to vfio-pci?)", nb_ports);
        return 1;
    }

    static struct client_io eth0;
    static struct eth1_io eth1;
    static struct flow_table ft;
    static struct packet_processor proc;
    static struct forwarder fwd;
    static struct pipeline_ctx pipeline;

    if (eth0_init(&eth0, 0, mbuf_pool, client_mac) < 0)
        return 1;
    if (eth1_init(&eth1, 1, mbuf_pool, gw_mac) < 0)
        return 1;

    ft_init(&ft);
    proc_init(&proc, &ft, &eth0, &eth1);
    fwd_init(&fwd, &ft, &eth0, &eth1);
    pipeline_init(&pipeline, &proc, &fwd, &eth0, &eth1, app_port, app_port_count);

    struct pcap_writer *capture = NULL;
    if (server_pcap_path) {
        if (pcap_writer_open(&capture, server_pcap_path) < 0)
            LOG_ERR("capture: failed to open %s — continuing without capture",
                    server_pcap_path);
    }

    install_iptables(app_port, app_port_count);

    signal(SIGINT,  signal_handler);
    signal(SIGTERM, signal_handler);

    LOG_INFO("Entering busy-poll loop...");

    struct rte_mbuf *rx_bufs0[RX_BURST_SIZE];
    struct rte_mbuf *rx_bufs1[RX_BURST_SIZE];

    while (running) {
        uint16_t nb_rx0 = rte_eth_rx_burst(eth0.port_id, 0, rx_bufs0, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx0; i++) {
            uint8_t *data = rte_pktmbuf_mtod(rx_bufs0[i], uint8_t *);
            uint16_t len  = rte_pktmbuf_data_len(rx_bufs0[i]);
            pipeline_feed_eth0(&pipeline, data, len);
            rte_pktmbuf_free(rx_bufs0[i]);
        }

        uint16_t nb_rx1 = rte_eth_rx_burst(eth1.port_id, 0, rx_bufs1, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx1; i++) {
            if (capture)
                pcap_writer_write_mbuf(capture, rx_bufs1[i]);
            pipeline_feed_eth1(&pipeline, rx_bufs1[i]);
            rte_pktmbuf_free(rx_bufs1[i]);
        }
    }

    LOG_INFO("Shutting down...");
    pcap_writer_close(capture);
    rte_eth_dev_stop(eth0.port_id);
    rte_eth_dev_close(eth0.port_id);
    rte_eth_dev_stop(eth1.port_id);
    rte_eth_dev_close(eth1.port_id);
    rte_eal_cleanup();
    return 0;
}
