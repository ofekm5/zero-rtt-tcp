#!/usr/bin/env bash
# Shared measurement helpers for experiment orchestrators.
# Source after ssm.sh. Requires: ssm_run, json_idx, pass, fail, warn.
#
# Load-generator knobs (single source of truth; override via env):
#   IPERF_PARALLEL : total parallel TCP connections per round (default 100000)
#   IPERF_PORTS    : number of contiguous server ports the load is spread across
#                    (default 4). 100000 conns / 4 ports = 25000 per (dst-port)
#                    tuple, comfortably under the ~28K-usable ephemeral range, so
#                    one client source IP can actually open them all. The 0-RTT
#                    data plane must cover the same port range (--port-count).
#   IPERF_TIMEOUT  : seconds a measurement round may run before SSM gives up
#                    (default 1800). 100000 conns x 1 MB across a 50 ms-netem path
#                    moves ~100 GB and takes far longer than the old 120 s cap —
#                    ssm_run polls up to this value instead of the ~100 s waiter.
#   IPERF_BYTES    : payload bytes sent per connection (default 1048576 = 1 MB,
#                    matching the old iperf `-n 1M`). At high connection counts
#                    this is bandwidth-delay-product bound (no window scaling +
#                    50ms netem caps a single flow well under 1 MB/s) and the
#                    aggregate pps across all flows can exceed the single-lcore
#                    forwarder's throughput (capacity-model.md §4/§9/§11) —
#                    lower this to validate connection *establishment* at scale
#                    without also demanding full-throughput transfer per flow.
IPERF_PARALLEL="${IPERF_PARALLEL:-100000}"
IPERF_PORTS="${IPERF_PORTS:-4}"
IPERF_TIMEOUT="${IPERF_TIMEOUT:-1800}"
IPERF_BYTES="${IPERF_BYTES:-1048576}"
#
# Measurement points (all intra-host intervals — no cross-machine clock sync):
#   - ClientNIC TTFB: stamped in clientnic-dpdk-forwarder (SYN ingress → 1st s2c data byte)
#   - ServerNIC TTFB: stamped in servernic-dpdk        (SYN ingress → 1st s2c data byte)
# Each NIC source emits [DIAG] rdtsc samples; the pcap analyzer emits structured lines:
#   metric=<name> value_ms=<v> node=<n> flow=...

# summarize_metric <metric> <node> <label>
# Reads text on stdin, extracts all matching analyzer output lines, prints count +
# min/mean/median/max in ms. No-op if none found.
# stdin is consumed into an env var so the heredoc can supply the Python script.
summarize_metric() {
    local metric="$1" node="$2" label="$3" data
    data="$(cat)"
    METRIC_DATA="$data" python3 - "$metric" "$node" "$label" <<'PY'
import os, sys, re, statistics
metric, node, label = sys.argv[1], sys.argv[2], sys.argv[3]
pat_metric = re.compile(r'\bmetric=' + re.escape(metric) + r'\b')
pat_node   = re.compile(r'\bnode='   + re.escape(node)   + r'\b')
pat_value  = re.compile(r'\bvalue_ms=([0-9.]+)')
vals = []
for line in os.environ.get("METRIC_DATA", "").splitlines():
    if not (pat_metric.search(line) and pat_node.search(line)):
        continue
    m = pat_value.search(line)
    if not m:
        continue
    vals.append(float(m.group(1)))
if not vals:
    print(f"  {label}: no samples found")
    sys.exit(0)
print(f"  {label}: n={len(vals)}  "
      f"min={min(vals):.3f}  mean={statistics.mean(vals):.3f}  "
      f"median={statistics.median(vals):.3f}  max={max(vals):.3f} ms")
PY
}

# report_nic_ttfb <log-text> <node>
# Convenience wrapper: summarise a NIC's per-flow TTFB from analyzer output.
report_nic_ttfb() {
    local log_text="$1" node="$2"
    echo "$log_text" | summarize_metric "ttfb" "$node" "$node TTFB (in-app)"
}

# run_ttfb_measurement <client-iid> <server-ip> <port> <count> <repo-path> [timeout-sec] [label]
# Runs <count> sequential rounds on the client VM via SSM. Each round opens
# IPERF_PARALLEL total parallel TCP connections, spread across IPERF_PORTS
# contiguous server ports ([port .. port+IPERF_PORTS-1]), via
# experiments/utils/loadgen.py — an asyncio (epoll-driven, single-thread)
# event-driven load generator. Replaces iperf2's -P N, which spawns N OS
# threads inside one process (25000 pthreads at 100k/4-ports is not viable at
# any instance size — see roadmap.md #20 scope item A / capacity-model.md).
# Sets globals: CLIENT_STDOUT, CLIENT_STDERR
run_ttfb_measurement() {
    local client_iid="$1" server_ip="$2" port="$3" count="$4" repo="$5"
    local timeout="${6:-${IPERF_TIMEOUT:-1800}}" label="${7:-Client}"
    local parallel="${IPERF_PARALLEL:-100000}"
    local nports="${IPERF_PORTS:-1}"
    [[ "$nports" -lt 1 ]] && nports=1
    local nbytes="${IPERF_BYTES:-1048576}"

    local result
    result=$(ssm_run "$client_iid" \
        "command -v python3 >/dev/null || { echo 'ERROR: python3 not installed'; exit 1; }
         ulimit -n 1048576 2>/dev/null || true
         success=0
         for i in \$(seq 1 $count); do
             echo \"--- Round \$i/$count: $nports port(s) starting at $port x $parallel total connections, $nbytes bytes/conn ---\"
             python3 $repo/experiments/utils/loadgen.py --mode client --host $server_ip --port $port --port-count $nports --parallel $parallel --bytes $nbytes && success=\$((success + 1))
         done
         echo \"Success: \${success}/$count\"" \
        "$timeout")

    CLIENT_STDOUT=$(echo "$result" | json_idx 1)
    CLIENT_STDERR=$(echo "$result" | json_idx 2)

    echo "--- $label output ---"
    echo "$CLIENT_STDOUT"
    [[ -n "$CLIENT_STDERR" ]] && echo "stderr: $CLIENT_STDERR"
    echo "---"

    if echo "$CLIENT_STDOUT" | grep -qE "Success: ${count}/${count}"; then
        pass "$label: all $count connection(s) succeeded"
    elif echo "$CLIENT_STDOUT" | grep -qE "Success: [1-9][0-9]*/${count}"; then
        warn "$label: partial success — see iperf output"
    else
        fail "$label: all $count connection(s) failed"
    fi
}
