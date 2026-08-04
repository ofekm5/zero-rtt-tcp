/*
 * eswitch-offload-probe: minimal DOCA Flow program that composes one pipe
 * entry in the e-switch (transfer) domain — 5-tuple match, a TCP
 * sequence-number modify action, egress back toward the host port, and a
 * hardware counter — per design.md D1.
 *
 * Rule parameters arrive as CLI arguments so syntax is iterated by
 * re-running the loaded container image rather than rebuilding it
 * (design.md "What Changes", tasks.md task 3).
 *
 * The rewrite is expressed through DOCA Flow's generic action-descriptor
 * mechanism (struct doca_flow_action_desc, DOCA_FLOW_ACTION_ADD over a
 * named header field), which is the documented way to apply arithmetic to
 * an arbitrary header field. The one value that still needs confirming
 * against the installed doca_flow.h on bluefield-runs3-dpu is the field
 * string itself — PROBE_TCP_SEQ_FIELD below — plus whether this build's
 * struct doca_flow_header_tcp carries seq_num. Both are isolated to the
 * two defines that follow so a correction is a one-line change (task 13).
 */

#include <arpa/inet.h>
#include <getopt.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rte_cycles.h>
#include <rte_eal.h>
#include <rte_ethdev.h>
#include <rte_mbuf.h>

#include <doca_argp.h>
#include <doca_dev.h>
#include <doca_error.h>
#include <doca_flow.h>
#include <doca_log.h>

DOCA_LOG_REGISTER(ESWITCH_PROBE);

/* DOCA Flow field string naming the TCP sequence number, and its width in
 * bits. Confirm against doca_flow.h on the target DPU (task 13); a wrong
 * string surfaces as a doca_flow_pipe_create rejection naming the field,
 * which is distinguishable from a silicon NO. */
#ifndef PROBE_TCP_SEQ_FIELD
#define PROBE_TCP_SEQ_FIELD "outer.tcp.seq_num"
#endif
#define PROBE_TCP_SEQ_WIDTH 32

/* IPv4 dotted-quad strings never exceed 15 chars + NUL; sized for IPv6 so
 * an over-long --src-ip is truncated rather than overflowing. Local so the
 * header list stays limited to DOCA/DPDK headers available in the devel
 * container. */
#define PROBE_IP_STR_LEN 46

#define DEFAULT_TIMEOUT_US 10000
#define DEFAULT_NB_COUNTERS 16
#define NB_RX_DESC 1024
#define MBUF_POOL_SIZE 4096
#define MBUF_CACHE_SIZE 256
#define RX_BURST_SIZE 32
#define SW_QUEUE_POLL_MS 200
#define SW_QUEUE_POLL_INTERVAL_MS 10

/* Emitted on stdout the moment the rule is live, before the hold window
 * begins. The orchestrator blocks on this line before generating traffic —
 * it is the handshake that guarantees the rule is installed while packets
 * are on the wire, rather than created and torn down around them. */
#define RULE_INSTALLED_MARKER "RULE INSTALLED"

struct probe_config {
	char src_ip[PROBE_IP_STR_LEN];
	char dst_ip[PROBE_IP_STR_LEN];
	uint16_t src_port;
	uint16_t dst_port;
	int32_t delta;      /* per-flow constant applied to the TCP seq number */
	char direction[8];  /* "sub" (client->server ack) or "add" (server->client seq) */
	uint16_t port_id;   /* DPDK/DOCA port id for pf0hpf (egress target) */
	uint32_t hold_secs; /* seconds to keep the rule installed; 0 = SW_QUEUE_POLL_MS */
};

static struct probe_config g_cfg = {
	.src_ip = "0.0.0.0",
	.dst_ip = "0.0.0.0",
	.src_port = 0,
	.dst_port = 0,
	.delta = 0,
	.direction = "sub",
	.port_id = 0,
	.hold_secs = 0,
};

/* Parses a dotted-quad IPv4 string into network-byte-order form, matching
 * doca_flow_ip4_addr's expected representation. */
static doca_error_t
probe_parse_ipv4(const char *ip_str, uint32_t *out_be)
{
	struct in_addr addr;

	if (inet_pton(AF_INET, ip_str, &addr) != 1) {
		DOCA_LOG_ERR("Invalid IPv4 address: %s", ip_str);
		return DOCA_ERROR_INVALID_VALUE;
	}
	*out_be = addr.s_addr;
	return DOCA_SUCCESS;
}

/* The signed constant this run adds to the TCP sequence number. "sub" is
 * expressed as an ADD of the two's complement, which is exactly TCP's own
 * 32-bit wraparound arithmetic — so one action type covers both
 * directions and there is no second code path to get wrong. */
static uint32_t
probe_seq_addend(void)
{
	return (strcmp(g_cfg.direction, "sub") == 0)
		       ? (uint32_t)(-(int64_t)g_cfg.delta)
		       : (uint32_t)g_cfg.delta;
}

static void
usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s --src-ip <ip> --dst-ip <ip> --src-port <port> --dst-port <port> "
		"--delta <int32> [--direction sub|add] [--port-id <id>] [--hold-secs <n>]\n",
		prog);
}

/* Parses argv into g_cfg. Rule parameters are CLI arguments (design.md
 * "What Changes") so the 5-tuple, delta and direction can be iterated by
 * re-running this binary rather than rebuilding it. */
static doca_error_t
probe_parse_args(int argc, char **argv)
{
	static const struct option long_opts[] = {
		{"src-ip", required_argument, NULL, 's'},
		{"dst-ip", required_argument, NULL, 'd'},
		{"src-port", required_argument, NULL, 'p'},
		{"dst-port", required_argument, NULL, 'q'},
		{"delta", required_argument, NULL, 'c'},
		{"direction", required_argument, NULL, 'r'},
		{"port-id", required_argument, NULL, 'i'},
		{"hold-secs", required_argument, NULL, 'H'},
		{NULL, 0, NULL, 0},
	};
	int opt;
	int has_src_ip = 0, has_dst_ip = 0, has_src_port = 0, has_dst_port = 0, has_delta = 0;

	while ((opt = getopt_long(argc, argv, "s:d:p:q:c:r:i:H:", long_opts, NULL)) != -1) {
		switch (opt) {
		case 's':
			strncpy(g_cfg.src_ip, optarg, sizeof(g_cfg.src_ip) - 1);
			has_src_ip = 1;
			break;
		case 'd':
			strncpy(g_cfg.dst_ip, optarg, sizeof(g_cfg.dst_ip) - 1);
			has_dst_ip = 1;
			break;
		case 'p':
			g_cfg.src_port = (uint16_t)atoi(optarg);
			has_src_port = 1;
			break;
		case 'q':
			g_cfg.dst_port = (uint16_t)atoi(optarg);
			has_dst_port = 1;
			break;
		case 'c':
			g_cfg.delta = (int32_t)atol(optarg);
			has_delta = 1;
			break;
		case 'r':
			strncpy(g_cfg.direction, optarg, sizeof(g_cfg.direction) - 1);
			break;
		case 'i':
			g_cfg.port_id = (uint16_t)atoi(optarg);
			break;
		case 'H':
			g_cfg.hold_secs = (uint32_t)strtoul(optarg, NULL, 10);
			break;
		default:
			usage(argv[0]);
			return DOCA_ERROR_INVALID_VALUE;
		}
	}

	if (!has_src_ip || !has_dst_ip || !has_src_port || !has_dst_port || !has_delta) {
		DOCA_LOG_ERR("Missing required argument (--src-ip/--dst-ip/--src-port/--dst-port/--delta)");
		usage(argv[0]);
		return DOCA_ERROR_INVALID_VALUE;
	}
	return DOCA_SUCCESS;
}

/* Initialises DOCA Flow in the e-switch (transfer) domain with hardware
 * steering, per design.md D1 ("build its pipe in the e-switch domain
 * rather than as a NIC-domain rule"). */
/* Configures pf0hpf's RX queue at the DPDK level so the software path is
 * actually pollable — DOCA Flow's hardware forward path never traverses
 * this queue, so any packet landing here during dpdk_rx_poll_sw_queue()
 * is genuine evidence of a software fallback (SC3), not an assumption. */
static doca_error_t
dpdk_rx_setup(struct rte_mempool **mbuf_pool)
{
	struct rte_eth_conf port_conf = {0};
	int ret;

	*mbuf_pool = rte_pktmbuf_pool_create("probe_mbuf_pool", MBUF_POOL_SIZE, MBUF_CACHE_SIZE,
					      0, RTE_MBUF_DEFAULT_BUF_SIZE, rte_socket_id());
	if (*mbuf_pool == NULL) {
		DOCA_LOG_ERR("rte_pktmbuf_pool_create failed: %s", rte_strerror(rte_errno));
		return DOCA_ERROR_NO_MEMORY;
	}

	ret = rte_eth_dev_configure(g_cfg.port_id, 1, 0, &port_conf);
	if (ret != 0) {
		DOCA_LOG_ERR("rte_eth_dev_configure failed: %s", rte_strerror(-ret));
		return DOCA_ERROR_DRIVER;
	}

	ret = rte_eth_rx_queue_setup(g_cfg.port_id, 0, NB_RX_DESC,
				      rte_eth_dev_socket_id(g_cfg.port_id), NULL, *mbuf_pool);
	if (ret != 0) {
		DOCA_LOG_ERR("rte_eth_rx_queue_setup failed: %s", rte_strerror(-ret));
		return DOCA_ERROR_DRIVER;
	}

	ret = rte_eth_dev_start(g_cfg.port_id);
	if (ret != 0) {
		DOCA_LOG_ERR("rte_eth_dev_start failed: %s", rte_strerror(-ret));
		return DOCA_ERROR_DRIVER;
	}

	return DOCA_SUCCESS;
}

/* Polls the ARM software RX queue for the hold window and returns the count
 * of packets received there — a real measurement, not an assumed zero. A
 * nonzero count means packets matching the composed rule are crossing an
 * ARM core instead of staying in hardware (SC3).
 *
 * The window doubles as the rule's lifetime: the entry stays installed for
 * exactly as long as this polls, which is what lets a separately-invoked
 * traffic generator hit a live rule. --hold-secs sizes it to cover the
 * orchestrator's traffic step; without it the window is the short default,
 * useful only for the port-init smoke check in setup.sh. */
static uint64_t
dpdk_rx_poll_sw_queue(void)
{
	struct rte_mbuf *bufs[RX_BURST_SIZE];
	uint64_t total = 0, elapsed_ms = 0;
	const uint64_t window_ms = g_cfg.hold_secs > 0
					   ? (uint64_t)g_cfg.hold_secs * 1000
					   : SW_QUEUE_POLL_MS;

	while (elapsed_ms < window_ms) {
		uint16_t nb_rx = rte_eth_rx_burst(g_cfg.port_id, 0, bufs, RX_BURST_SIZE);
		for (uint16_t i = 0; i < nb_rx; i++)
			rte_pktmbuf_free(bufs[i]);
		total += nb_rx;
		rte_delay_ms(SW_QUEUE_POLL_INTERVAL_MS);
		elapsed_ms += SW_QUEUE_POLL_INTERVAL_MS;
	}
	return total;
}

static doca_error_t
probe_flow_init(void)
{
	struct doca_flow_cfg flow_cfg = {0};
	doca_error_t result;

	flow_cfg.pipe_queues = 1;
	flow_cfg.mode_args = "switch,hws";
	flow_cfg.resource.nb_counters = DEFAULT_NB_COUNTERS;

	result = doca_flow_init(&flow_cfg);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_init failed: %s", doca_error_get_descr(result));
		return result;
	}
	return DOCA_SUCCESS;
}

/* Starts pf0hpf as the data-plane port (SC1: "the probe's startup output
 * reports pf0hpf initialised without error"). */
static doca_error_t
probe_port_start(struct doca_flow_port **port)
{
	struct doca_flow_port_cfg port_cfg = {0};
	doca_error_t result;

	port_cfg.port_id = g_cfg.port_id;
	port_cfg.type = DOCA_FLOW_PORT_DPDK_BY_ID;

	result = doca_flow_port_start(&port_cfg, port);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_port_start failed for pf0hpf (port_id=%u): %s",
			     g_cfg.port_id, doca_error_get_descr(result));
		return result;
	}
	DOCA_LOG_INFO("pf0hpf initialised (port_id=%u)", g_cfg.port_id);
	return DOCA_SUCCESS;
}

/* Composes the single pipe entry the spike needs: match the 5-tuple,
 * modify the TCP sequence number by g_cfg.delta, egress back toward the
 * host port, and attach a counter (design.md D1 / D2's "Offloaded" level).
 */
static doca_error_t
probe_pipe_create(struct doca_flow_port *port, struct doca_flow_pipe **pipe)
{
	struct doca_flow_match match = {0};
	struct doca_flow_actions actions = {0};
	struct doca_flow_actions *actions_arr[] = {&actions};
	struct doca_flow_action_desc seq_desc = {0};
	struct doca_flow_action_descs descs = {0};
	struct doca_flow_action_descs *descs_arr[] = {&descs};
	struct doca_flow_fwd fwd = {0};
	struct doca_flow_fwd fwd_miss = {0};
	struct doca_flow_pipe_cfg pipe_cfg = {0};
	uint32_t src_ip_be, dst_ip_be;
	doca_error_t result;

	result = probe_parse_ipv4(g_cfg.src_ip, &src_ip_be);
	if (result != DOCA_SUCCESS)
		return result;
	result = probe_parse_ipv4(g_cfg.dst_ip, &dst_ip_be);
	if (result != DOCA_SUCCESS)
		return result;

	match.parser_meta.outer_l3_type = DOCA_FLOW_L3_META_IPV4;
	match.parser_meta.outer_l4_type = DOCA_FLOW_L4_META_TCP;
	match.outer.l3_type = DOCA_FLOW_L3_TYPE_IP4;
	match.outer.l4_type_ext = DOCA_FLOW_L4_TYPE_EXT_TCP;
	match.outer.ip4.src_ip = src_ip_be;
	match.outer.ip4.dst_ip = dst_ip_be;
	match.outer.tcp.l4_port.src_port = rte_cpu_to_be_16(g_cfg.src_port);
	match.outer.tcp.l4_port.dst_port = rte_cpu_to_be_16(g_cfg.dst_port);

	/* Modify action: add a per-flow constant to the TCP sequence number.
	 * The descriptor names the field and the arithmetic; the value itself
	 * is supplied per entry (probe_entry_add). At pipe level the field is
	 * set to an all-ones mask, which is how DOCA Flow is told the field is
	 * modified by this pipe. src.field_string stays NULL so the addend is
	 * taken as an immediate from the actions struct rather than copied
	 * from another header field. */
	seq_desc.type = DOCA_FLOW_ACTION_ADD;
	seq_desc.field_op.dst.field_string = PROBE_TCP_SEQ_FIELD;
	seq_desc.field_op.dst.bit_offset = 0;
	seq_desc.field_op.src.field_string = NULL;
	seq_desc.field_op.src.bit_offset = 0;
	seq_desc.field_op.width = PROBE_TCP_SEQ_WIDTH;

	descs.nb_action_desc = 1;
	descs.desc_array = &seq_desc;

	actions.outer.tcp.seq_num = UINT32_MAX;

	fwd.type = DOCA_FLOW_FWD_PORT;
	fwd.port_id = g_cfg.port_id;

	fwd_miss.type = DOCA_FLOW_FWD_DROP;

	pipe_cfg.attr.name = "eswitch_probe_pipe";
	pipe_cfg.attr.type = DOCA_FLOW_PIPE_BASIC;
	pipe_cfg.attr.domain = DOCA_FLOW_PIPE_DOMAIN_DEFAULT;
	pipe_cfg.attr.is_root = true;
	pipe_cfg.match = &match;
	pipe_cfg.actions = actions_arr;
	pipe_cfg.action_descs = descs_arr;
	pipe_cfg.attr.nb_actions = 1;
	pipe_cfg.port = port;

	result = doca_flow_pipe_create(&pipe_cfg, &fwd, &fwd_miss, pipe);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_pipe_create failed (rule not accepted): %s",
			     doca_error_get_descr(result));
		return result;
	}
	return DOCA_SUCCESS;
}

/* Adds the single flow entry (the composed rule) and attaches a
 * non-shared counter — SC2 ("the rule-creation call returns a valid
 * handle") and SC3's hardware-counter signal. */
static doca_error_t
probe_entry_add(struct doca_flow_port *port, struct doca_flow_pipe *pipe,
		 struct doca_flow_pipe_entry **entry)
{
	struct doca_flow_match match = {0};
	struct doca_flow_actions actions = {0};
	struct doca_flow_monitor monitor = {0};
	struct doca_flow_fwd fwd = {0};
	uint32_t src_ip_be, dst_ip_be;
	doca_error_t result;

	result = probe_parse_ipv4(g_cfg.src_ip, &src_ip_be);
	if (result != DOCA_SUCCESS)
		return result;
	result = probe_parse_ipv4(g_cfg.dst_ip, &dst_ip_be);
	if (result != DOCA_SUCCESS)
		return result;

	match.outer.ip4.src_ip = src_ip_be;
	match.outer.ip4.dst_ip = dst_ip_be;
	match.outer.tcp.l4_port.src_port = rte_cpu_to_be_16(g_cfg.src_port);
	match.outer.tcp.l4_port.dst_port = rte_cpu_to_be_16(g_cfg.dst_port);

	/* The actual addend for this entry. The pipe's descriptor already
	 * named the field and the ADD; this supplies the immediate. */
	actions.outer.tcp.seq_num = probe_seq_addend();

	monitor.counter_type = DOCA_FLOW_RESOURCE_TYPE_NON_SHARED;

	fwd.type = DOCA_FLOW_FWD_PORT;
	fwd.port_id = g_cfg.port_id;

	result = doca_flow_pipe_add_entry(0, pipe, &match, &actions, &monitor, &fwd, 0, NULL, entry);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_pipe_add_entry failed: %s", doca_error_get_descr(result));
		return result;
	}

	result = doca_flow_entries_process(port, 0, DEFAULT_TIMEOUT_US, 0);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_entries_process failed: %s", doca_error_get_descr(result));
		return result;
	}

	DOCA_LOG_INFO("Rule accepted: handle=%p", (void *)*entry);
	return DOCA_SUCCESS;
}

/* Reports the entry's hardware counter and this process's own
 * software-queue receive count, side by side — SC3 distinguishes a
 * hardware hit from a software fallback by comparing the two. */
static void
probe_report_counters(struct doca_flow_pipe_entry *entry, uint64_t sw_queue_rx_count)
{
	struct doca_flow_query query_stats = {0};
	doca_error_t result;

	result = doca_flow_query_entry(entry, &query_stats);
	if (result != DOCA_SUCCESS) {
		DOCA_LOG_ERR("doca_flow_query_entry failed: %s", doca_error_get_descr(result));
		printf("COUNTER: query-failed\n");
	} else {
		printf("COUNTER: total_pkts=%lu total_bytes=%lu\n",
		       (unsigned long)query_stats.total_pkts,
		       (unsigned long)query_stats.total_bytes);
	}
	printf("SW_QUEUE_RX_COUNT: %lu\n", (unsigned long)sw_queue_rx_count);
}

int
main(int argc, char **argv)
{
	struct doca_flow_port *port = NULL;
	struct doca_flow_pipe *pipe = NULL;
	struct doca_flow_pipe_entry *entry = NULL;
	struct rte_mempool *mbuf_pool = NULL;
	uint64_t sw_queue_rx_count = 0;
	doca_error_t result;
	int rc = EXIT_SUCCESS;
	int rte_argc;

	/* DPDK EAL args (-l, -n, -a auxiliary:mlx5_core.sf.N[,dv_flow_en=2])
	 * precede a "--" separator; the probe's own rule-parameter args
	 * follow it. rte_eal_init consumes its prefix and reports how many
	 * argv entries it used so the remainder reaches probe_parse_args. */
	rte_argc = rte_eal_init(argc, argv);
	if (rte_argc < 0) {
		fprintf(stderr, "rte_eal_init failed\n");
		return EXIT_FAILURE;
	}
	argc -= rte_argc;
	argv += rte_argc;
	optind = 1; /* reset getopt state after EAL's own arg parsing */

	result = probe_parse_args(argc, argv);
	if (result != DOCA_SUCCESS)
		return EXIT_FAILURE;

	result = dpdk_rx_setup(&mbuf_pool);
	if (result != DOCA_SUCCESS)
		return EXIT_FAILURE;

	result = probe_flow_init();
	if (result != DOCA_SUCCESS)
		return EXIT_FAILURE;

	result = probe_port_start(&port);
	if (result != DOCA_SUCCESS) {
		rc = EXIT_FAILURE;
		goto teardown_flow;
	}

	result = probe_pipe_create(port, &pipe);
	if (result != DOCA_SUCCESS) {
		rc = EXIT_FAILURE;
		goto teardown_port;
	}

	result = probe_entry_add(port, pipe, &entry);
	if (result != DOCA_SUCCESS) {
		rc = EXIT_FAILURE;
		goto teardown_pipe;
	}

	/* The rule is live from here until dpdk_rx_poll_sw_queue returns.
	 * Announce it on stdout and flush immediately: the orchestrator waits
	 * for this line before running traffic.sh, so the packets it sends
	 * arrive while the entry is installed. Without the handshake the rule
	 * would be created and removed around the traffic window rather than
	 * across it, and the counter would be read before any packet existed. */
	printf("%s (hold_secs=%u)\n", RULE_INSTALLED_MARKER, g_cfg.hold_secs);
	fflush(stdout);

	/* Real measurement, not an assumed zero: any packet landing on the
	 * ARM software queue during this window is evidence the rule fell
	 * back to software rather than executing in hardware (SC3). */
	sw_queue_rx_count = dpdk_rx_poll_sw_queue();
	probe_report_counters(entry, sw_queue_rx_count);

	doca_flow_pipe_rm_entry(0, 0, entry);
teardown_pipe:
	doca_flow_pipe_destroy(pipe);
teardown_port:
	doca_flow_port_stop(port);
teardown_flow:
	doca_flow_destroy();
	rte_eal_cleanup();
	return rc;
}
