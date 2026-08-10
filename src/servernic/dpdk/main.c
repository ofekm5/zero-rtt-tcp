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
#include "wan_delay.h"
#include "log.h"

#define MBUF_CACHE_SIZE 250
#define RX_BURST_SIZE   32
#define RX_RING_SIZE    1024   /* must match io.c */
#define TX_RING_SIZE    1024   /* must match io.c */
/* NUM_MBUFS ≥ nb_ports * (nb_rxd + nb_txd + max_burst + nb_lcores * cache),
 * derived instead of a bare magic number so a third port or deeper ring can't
 * silently push headroom under the minimum (capacity-model.md §3).
 * WAN_DELAY_RING is added on top: with --wan-delay-us set, that many mbufs can
 * be held in the emulated-WAN queue and are unavailable to the RX path. */
#define MBUF_POOL_SIZE  (RTE_MAX((unsigned)(2 * (RX_RING_SIZE + TX_RING_SIZE + \
                                 RX_BURST_SIZE + MBUF_CACHE_SIZE)), 8191U) \
                         + (unsigned)WAN_DELAY_RING)
#define STATS_INTERVAL_SEC 5   /* seconds between periodic per-port stats logs */

static volatile int running = 1;
static uint64_t g_truncated_frames = 0; /* pkt_len != data_len — see capacity-model.md §5 */

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
    uint32_t wan_delay_us = 0;          /* emulated WAN on the middle leg */

    static struct option long_opts[] = {
        {"port",             required_argument, NULL, 'p'},
        {"port-count",       required_argument, NULL, 'n'},
        {"gw-mac",           required_argument, NULL, 'g'},
        {"server-mac",       required_argument, NULL, 'G'},
        {"client-port-mac",  required_argument, NULL, 'c'},
        {"server-port-mac",  required_argument, NULL, 's'},
        {"wan-delay-us",     required_argument, NULL, 'D'},
        {NULL, 0, NULL, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "p:n:g:G:c:s:D:", long_opts, NULL)) != -1) {
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
        case 'D':
            wan_delay_us = (uint32_t)strtoul(optarg, NULL, 10);
            break;
        default:
            fprintf(stderr,
                    "Usage: %s [EAL opts] -- --port=PORT [--port-count=N]"
                    " --gw-mac=CLIENTNIC_GW_MAC --server-mac=SERVER_MAC"
                    " --client-port-mac=MAC --server-port-mac=MAC"
                    " [--wan-delay-us=N]\n", argv[0]);
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

    if (eth1_init(&eth1, client_port_id, mbuf_pool, gw_mac, wan_delay_us) < 0)
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

    const uint64_t stats_period = rte_get_tsc_hz() * STATS_INTERVAL_SEC;
    uint64_t next_stats = rte_rdtsc() + stats_period;
    unsigned mempool_low_water = MBUF_POOL_SIZE;  /* min free mbufs observed */
    uint64_t proc_cycles = 0;   /* cycles spent actually processing packets (capacity-model §9/§12) */
    uint64_t proc_packets = 0;  /* packets those cycles were spent on — excludes idle-poll spin */

    while (running) {
        uint64_t iter_start = rte_rdtsc();

        /* Poll eth1 (DPDK rx_burst, from ClientNIC) */
        uint16_t nb_rx1 = rte_eth_rx_burst(eth1.port_id, 0, rx_bufs1, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx1; i++) {
            if (rte_pktmbuf_pkt_len(rx_bufs1[i]) != rte_pktmbuf_data_len(rx_bufs1[i]))
                g_truncated_frames++;
            pipeline_feed_eth1(&pipeline, rx_bufs1[i]);
            rte_pktmbuf_free(rx_bufs1[i]);
        }

        /* Poll eth2 (DPDK rx_burst, from Server) */
        uint16_t nb_rx2 = rte_eth_rx_burst(eth2.port_id, 0, rx_bufs2, RX_BURST_SIZE);
        for (uint16_t i = 0; i < nb_rx2; i++) {
            if (rte_pktmbuf_pkt_len(rx_bufs2[i]) != rte_pktmbuf_data_len(rx_bufs2[i]))
                g_truncated_frames++;
            pipeline_feed_eth2(&pipeline, rx_bufs2[i]);
            rte_pktmbuf_free(rx_bufs2[i]);
        }

        /* Release any middle-leg packets whose emulated WAN hold has expired.
         * Unconditional: it is a no-op without --wan-delay-us, and skipping it
         * on idle iterations would stall the queue exactly when there is no
         * new traffic to piggyback on. */
        eth1_wan_service(&eth1);

        /* Flush both TX batches once per loop iteration — amortizes the MMIO
         * doorbell write over up to TX_BATCH_SIZE packets instead of paying
         * it per packet (capacity-model.md §4/§9). */
        eth1_tx_flush(&eth1);
        eth2_tx_flush(&eth2);

        /* Attribute this iteration's cycles to the packets it processed —
         * skip empty iterations so idle busy-poll spin doesn't dilute the
         * per-packet cost (capacity-model.md §9/§12). */
        if (nb_rx1 || nb_rx2) {
            proc_cycles  += rte_rdtsc() - iter_start;
            proc_packets += (uint64_t)nb_rx1 + nb_rx2;
        }

        /* Sample pool headroom only while packets are in flight — that is when
         * the pool actually drains, and it keeps the count off the idle path. */
        if (nb_rx1 || nb_rx2) {
            unsigned avail = rte_mempool_avail_count(mbuf_pool);
            if (avail < mempool_low_water)
                mempool_low_water = avail;
        }

        uint64_t now = rte_rdtsc();
        if (now >= next_stats) {
            log_port_stats(eth1.port_id, "ClientNIC-facing");
            log_port_stats(eth2.port_id, "Server-facing");
            LOG_INFO("stats mempool: avail=%u/%d low-water=%u",
                     rte_mempool_avail_count(mbuf_pool), MBUF_POOL_SIZE,
                     mempool_low_water);
            if (g_truncated_frames)
                LOG_WARN("stats: truncated_frames=%" PRIu64 " total"
                         " — pkt_len != data_len, frame exceeded mbuf dataroom"
                         " (endpoint MTU > 2034B, capacity-model §5)",
                         g_truncated_frames);
            LOG_INFO("stats buffered: bytes=%" PRIu64 "/%" PRIu64 " (capacity-model §7)",
                     ft.buffered_bytes, (uint64_t)FT_MAX_BUFFERED_BYTES);
            if (proc_packets)
                LOG_INFO("stats cycles_per_packet: %.1f (tsc_hz=%" PRIu64
                         ", packets=%" PRIu64 ", capacity-model §9/§12)",
                         (double)proc_cycles / (double)proc_packets,
                         rte_get_tsc_hz(), proc_packets);
            if (wan_delay_enabled(&eth1.wan)) {
                LOG_INFO("stats wan_delay: held=%u/%u released=%" PRIu64,
                         wan_delay_count(&eth1.wan), WAN_DELAY_RING,
                         eth1.wan.passed);
                if (eth1.wan.dropped)
                    LOG_WARN("stats wan_delay: dropped=%" PRIu64 " — the hold"
                             " queue overflowed and manufactured packet loss,"
                             " which invalidates FCT for this run. Raise"
                             " WAN_DELAY_RING or lower the offered rate.",
                             eth1.wan.dropped);
            }
            next_stats = now + stats_period;
        }
    }

    LOG_INFO("Shutting down...");
    eth1_wan_flush_all(&eth1);
    eth1_tx_flush(&eth1);
    eth2_tx_flush(&eth2);
    rte_eth_dev_stop(eth1.port_id);
    rte_eth_dev_close(eth1.port_id);
    rte_eth_dev_stop(eth2.port_id);
    rte_eth_dev_close(eth2.port_id);
    rte_eal_cleanup();
    return 0;
}
