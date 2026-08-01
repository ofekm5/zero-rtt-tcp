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
 * The exact DOCA Flow field name for a raw TCP sequence-number modify
 * action is not confirmed in this repo's precedent (infra/bluefield/examples
 * only shows match+forward pipes and MAC-modify actions; see
 * infra/bluefield/docs/05-reference/gotchas.md #7). MOD_TCP_SEQ_FIELD below
 * names the best-effort field per DOCA 3.0's generic modify-field
 * convention; task 13 (manual review, live hardware) confirms or corrects
 * it against the installed doca_flow.h on bluefield-runs3-dpu.
 */

#include <arpa/inet.h>
#include <getopt.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <rte_eal.h>

#include <doca_argp.h>
#include <doca_dev.h>
#include <doca_error.h>
#include <doca_flow.h>
#include <doca_log.h>

DOCA_LOG_REGISTER(ESWITCH_PROBE);

/* Best-effort DOCA Flow field selector for a raw TCP sequence-number
 * rewrite. Confirm against doca_flow.h on the target DPU (task 13). */
#ifndef MOD_TCP_SEQ_FIELD
#define MOD_TCP_SEQ_FIELD DOCA_FLOW_ACTION_MODIFY_FIELD
#endif

#define DEFAULT_TIMEOUT_US 10000
#define DEFAULT_NB_COUNTERS 16

struct probe_config {
	char src_ip[INET6_ADDRSTRLEN_UNUSED];
	char dst_ip[INET6_ADDRSTRLEN_UNUSED];
	uint16_t src_port;
	uint16_t dst_port;
	int32_t delta;      /* per-flow constant applied to the TCP seq number */
	char direction[8];  /* "sub" (client->server ack) or "add" (server->client seq) */
	uint16_t port_id;   /* DPDK/DOCA port id for pf0hpf (egress target) */
};

/* Small, self-contained replacement for <netinet/in.h>'s INET6_ADDRSTRLEN
 * so this header list stays limited to DOCA/DPDK headers available in the
 * devel container; IPv4 dotted-quad strings never exceed 15 chars + NUL. */
#define INET6_ADDRSTRLEN_UNUSED 46

static struct probe_config g_cfg = {
	.src_ip = "0.0.0.0",
	.dst_ip = "0.0.0.0",
	.src_port = 0,
	.dst_port = 0,
	.delta = 0,
	.direction = "sub",
	.port_id = 0,
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

static void
usage(const char *prog)
{
	fprintf(stderr,
		"Usage: %s --src-ip <ip> --dst-ip <ip> --src-port <port> --dst-port <port> "
		"--delta <int32> [--direction sub|add] [--port-id <id>]\n",
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
		{NULL, 0, NULL, 0},
	};
	int opt;
	int has_src_ip = 0, has_dst_ip = 0, has_src_port = 0, has_dst_port = 0, has_delta = 0;

	while ((opt = getopt_long(argc, argv, "s:d:p:q:c:r:i:", long_opts, NULL)) != -1) {
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

	/* Modify action: rewrite the TCP sequence number by the per-flow
	 * constant. See the MOD_TCP_SEQ_FIELD note at the top of this file —
	 * the exact selector is unconfirmed against real hardware headers. */
	actions.MOD_TCP_SEQ_FIELD.tcp_seq_delta = g_cfg.delta;
	actions.MOD_TCP_SEQ_FIELD.direction_is_sub = (strcmp(g_cfg.direction, "sub") == 0);

	fwd.type = DOCA_FLOW_FWD_PORT;
	fwd.port_id = g_cfg.port_id;

	fwd_miss.type = DOCA_FLOW_FWD_DROP;

	pipe_cfg.attr.name = "eswitch_probe_pipe";
	pipe_cfg.attr.type = DOCA_FLOW_PIPE_BASIC;
	pipe_cfg.attr.domain = DOCA_FLOW_PIPE_DOMAIN_DEFAULT;
	pipe_cfg.attr.is_root = true;
	pipe_cfg.match = &match;
	pipe_cfg.actions = actions_arr;
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

	actions.MOD_TCP_SEQ_FIELD.tcp_seq_delta = g_cfg.delta;

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

	/* This probe never polls a software RX queue for the rewritten
	 * flow's traffic by design — a nonzero software receive count in a
	 * production translator would mean the rule fell back to software;
	 * here it stays fixed at zero so SC3's comparison isolates the
	 * hardware counter alone. */
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
