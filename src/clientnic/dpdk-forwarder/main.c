#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <getopt.h>
#include <inttypes.h>

#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>
#include <rte_cycles.h>
#include <rte_mempool.h>

#include "pipeline.h"
#include "capture.h"
#include "log.h"

#define MBUF_POOL_SIZE  8191
#define MBUF_CACHE_SIZE 250
#define RX_BURST_SIZE   32
#define STATS_INTERVAL_SEC 5   /* seconds between periodic per-port stats logs */

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

/* Periodic per-port drop/error visibility. imissed and rx_nombuf look identical
 * from the outside (throughput collapses) but have opposite fixes, so log them
 * separately with the diagnosis attached. See docs/capacity-model.md §11. */
static void log_port_stats(uint16_t port_id, const char *name)
{
    struct rte_eth_stats st;
    if (rte_eth_stats_get(port_id, &st) != 0) {
        LOG_WARN("stats %s (port %u): rte_eth_stats_get failed", name, port_id);
        return;
    }
    LOG_INFO("stats %s (port %u): rx=%" PRIu64 " tx=%" PRIu64
             " imissed=%" PRIu64 " rx_nombuf=%" PRIu64
             " ierrors=%" PRIu64 " oerrors=%" PRIu64,
             name, port_id, st.ipackets, st.opackets,
             st.imissed, st.rx_nombuf, st.ierrors, st.oerrors);
    if (st.imissed)
        LOG_WARN("stats %s (port %u): imissed=%" PRIu64
                 " — RX ring overflowed, core too slow (capacity-model §11)",
                 name, port_id, st.imissed);
    if (st.rx_nombuf)
        LOG_WARN("stats %s (port %u): rx_nombuf=%" PRIu64
                 " — mempool ran dry, pool too small or mbuf leak (capacity-model §11)",
                 name, port_id, st.rx_nombuf);
    if (st.oerrors)
        LOG_WARN("stats %s (port %u): oerrors=%" PRIu64
                 " — TX errors, downstream/link (capacity-model §11)",
                 name, port_id, st.oerrors);
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
    uint8_t  gw_mac[6] = {0};              /* peer: ServerNIC eth1 (TX destination) */
    int      gw_mac_set = 0;
    uint8_t  client_port_mac[6] = {0};     /* local: our client-facing ENI  */
    int      client_port_mac_set = 0;
    uint8_t  server_port_mac[6] = {0};     /* local: our ServerNIC-facing ENI */
    int      server_port_mac_set = 0;
    const char *server_pcap_path = NULL;

    static struct option long_opts[] = {
        {"port",             required_argument, NULL, 'p'},
        {"port-count",       required_argument, NULL, 'n'},
        {"gw-mac",           required_argument, NULL, 'g'},
        {"client-port-mac",  required_argument, NULL, 'm'},
        {"server-port-mac",  required_argument, NULL, 'M'},
        {"server-pcap",      required_argument, NULL, 'w'},
        {NULL, 0, NULL, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "p:n:g:m:M:w:", long_opts, NULL)) != -1) {
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
            if (parse_mac(optarg, client_port_mac) < 0) {
                LOG_ERR("Invalid --client-port-mac: %s", optarg);
                return 1;
            }
            client_port_mac_set = 1;
            break;
        case 'M':
            if (parse_mac(optarg, server_port_mac) < 0) {
                LOG_ERR("Invalid --server-port-mac: %s", optarg);
                return 1;
            }
            server_port_mac_set = 1;
            break;
        case 'w':
            server_pcap_path = optarg;
            break;
        default:
            fprintf(stderr,
                    "Usage: %s [EAL opts] -- --port=PORT [--port-count=N]"
                    " --gw-mac=MAC --client-port-mac=MAC --server-port-mac=MAC"
                    " [--server-pcap=FILE]\n", argv[0]);
            return 1;
        }
    }

    if (!gw_mac_set) {
        LOG_ERR("--gw-mac (ServerNIC eth1 peer MAC) is required");
        return 1;
    }
    if (!client_port_mac_set) {
        LOG_ERR("--client-port-mac (our client-facing ENI MAC) is required");
        return 1;
    }
    if (!server_port_mac_set) {
        LOG_ERR("--server-port-mac (our ServerNIC-facing ENI MAC) is required");
        return 1;
    }

    LOG_INFO("ClientNIC DPDK Forwarder starting (port=%u..%u)",
             app_port, (uint16_t)(app_port + app_port_count - 1));
    LOG_INFO("Gateway MAC: %02x:%02x:%02x:%02x:%02x:%02x",
             gw_mac[0], gw_mac[1], gw_mac[2],
             gw_mac[3], gw_mac[4], gw_mac[5]);

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

    /* Map roles to ports by MAC, never by port ID: DPDK numbers ports in PCI
     * order, which does not reliably follow ENI device_index, so a hardcoded
     * 0/1 split can silently swap the client and ServerNIC links. */
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
    LOG_INFO("Port map: client-facing=port %u, ServerNIC-facing=port %u",
             client_port_id, server_port_id);

    static struct client_io eth0;
    static struct eth1_io eth1;
    static struct flow_table ft;
    static struct packet_processor proc;
    static struct forwarder fwd;
    static struct pipeline_ctx pipeline;

    if (eth0_init(&eth0, client_port_id, mbuf_pool) < 0)
        return 1;
    if (eth1_init(&eth1, server_port_id, mbuf_pool, gw_mac) < 0)
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

    const uint64_t stats_period = rte_get_tsc_hz() * STATS_INTERVAL_SEC;
    uint64_t next_stats = rte_rdtsc() + stats_period;
    unsigned mempool_low_water = MBUF_POOL_SIZE;  /* min free mbufs observed */

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

        /* Sample pool headroom only while packets are in flight — that is when
         * the pool actually drains, and it keeps the count off the idle path. */
        if (nb_rx0 || nb_rx1) {
            unsigned avail = rte_mempool_avail_count(mbuf_pool);
            if (avail < mempool_low_water)
                mempool_low_water = avail;
        }

        uint64_t now = rte_rdtsc();
        if (now >= next_stats) {
            log_port_stats(eth0.port_id, "client-facing");
            log_port_stats(eth1.port_id, "ServerNIC-facing");
            LOG_INFO("stats mempool: avail=%u/%d low-water=%u",
                     rte_mempool_avail_count(mbuf_pool), MBUF_POOL_SIZE,
                     mempool_low_water);
            next_stats = now + stats_period;
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
