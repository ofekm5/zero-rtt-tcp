#!/usr/bin/env bash
# Shared measurement helpers for experiment orchestrators.
# Source after ssm.sh. Requires: ssm_run, json_idx, log, pass, fail, warn.
#
# Load-generator knobs (single source of truth; override via env):
#   LOAD_PARALLEL : total parallel TCP connections per round (default 100000)
#   LOAD_PORTS    : number of contiguous server ports the load is spread across
#                    (default 4). 100000 conns / 4 ports = 25000 per (dst-port)
#                    tuple, comfortably under the ~28K-usable ephemeral range, so
#                    one client source IP can actually open them all. The 0-RTT
#                    data plane must cover the same port range (--port-count).
#   LOAD_TIMEOUT  : seconds a measurement round may run before SSM gives up
#                    (default 1800). 100000 conns x 1 MB across a 50 ms-netem path
#                    moves ~100 GB and takes far longer than the old 120 s cap —
#                    ssm_run polls up to this value instead of the ~100 s waiter.
#   LOAD_BYTES    : payload bytes sent per connection (default 1024 = one
#                    segment). The old 1 MB default (matching iperf `-n 1M`) is
#                    bandwidth-delay-product bound: with window scaling disabled
#                    and 50ms netem, one flow is capped near 640 KB/s, so 1 MB
#                    costs ~16 RTTs of transfer and the single RTT that 0-RTT
#                    eliminates is ~6% of flow completion time — below the
#                    run-to-run noise. One segment makes FCT ≈ handshake + 1 RTT,
#                    where the saving is the dominant term. Raise this only for a
#                    deliberate throughput comparison, never for latency claims.
#   LOAD_RATE     : connection arrival rate in connections/sec (default 2000).
#                    0 = burst (all LOAD_PARALLEL connections at once). Pacing
#                    is what makes per-connection latency meaningful: in a burst
#                    every flow's measured latency includes queueing behind every
#                    other SYN, so the run reports the forwarder's SYN service
#                    rate, not the round-trip the spoof removes. Paced, the same
#                    LOAD_PARALLEL total becomes N independent latency samples
#                    instead of one saturation event. Use 0 only for deliberate
#                    stress runs, which must not be read as latency results.
#   LOAD_CONCURRENCY : ceiling on simultaneously in-flight connections
#                    (default 2000). Bounds endpoint fd/RAM pressure regardless
#                    of pacing — per insights.md a t3.micro holds ~20–30k
#                    sockets, and exceeding it produced connection failures that
#                    were endpoint exhaustion, not data-plane defects.
LOAD_PARALLEL="${LOAD_PARALLEL:-100000}"
LOAD_PORTS="${LOAD_PORTS:-4}"
LOAD_TIMEOUT="${LOAD_TIMEOUT:-1800}"
LOAD_BYTES="${LOAD_BYTES:-1024}"
LOAD_RATE="${LOAD_RATE:-2000}"
LOAD_CONCURRENCY="${LOAD_CONCURRENCY:-2000}"
#
# Measurement points (all intra-host intervals — no cross-machine clock sync):
#   - ClientNIC TTFB: stamped in clientnic-dpdk-forwarder (SYN ingress → 1st s2c data byte)
#   - ServerNIC TTFB: stamped in servernic-dpdk        (SYN ingress → 1st s2c data byte)
# Each NIC source emits [DIAG] rdtsc samples; the pcap analyzer emits structured lines:
#   metric=<name> value_ms=<v> node=<n> flow=...
# or, under --summary, one pre-aggregated line per metric:
#   summary=<name> node=<n> n=<k> min_ms=.. p50_ms=.. p95_ms=.. p99_ms=.. max_ms=.. mean_ms=..

# summarize_metric <metric> <node> <label>
# Reads text on stdin, extracts all matching analyzer output lines, prints count +
# min/mean/median/max in ms. No-op if none found.
#
# Prefers a pre-aggregated summary= line when one is present: at 100k-connection
# scale the per-flow lines cannot survive the transport (AWS SSM truncates
# StandardOutputContent at 24 KB), so the analyzer aggregates on the capture host
# and only the summary crosses the wire. Falls back to per-flow lines otherwise,
# so small runs still report the identical shape.
# stdin is consumed into an env var so the heredoc can supply the Python script.
summarize_metric() {
    local metric="$1" node="$2" label="$3" data
    data="$(cat)"
    METRIC_DATA="$data" python3 - "$metric" "$node" "$label" <<'PY'
import os, sys, re, statistics
metric, node, label = sys.argv[1], sys.argv[2], sys.argv[3]
pat_metric  = re.compile(r'\bmetric='  + re.escape(metric) + r'\b')
pat_summary = re.compile(r'\bsummary=' + re.escape(metric) + r'\b')
pat_node    = re.compile(r'\bnode='    + re.escape(node)   + r'\b')
pat_value   = re.compile(r'\bvalue_ms=([0-9.]+)')
lines = os.environ.get("METRIC_DATA", "").splitlines()

# Preferred path: the analyzer already aggregated on the capture host.
for line in lines:
    if not (pat_summary.search(line) and pat_node.search(line)):
        continue
    f = dict(re.findall(r'(\w+)=([0-9.]+)', line))
    if "n" not in f:
        continue
    print(f"  {label}: n={f['n']}  "
          f"min={float(f.get('min_ms', 0)):.3f}  mean={float(f.get('mean_ms', 0)):.3f}  "
          f"median={float(f.get('p50_ms', 0)):.3f}  p95={float(f.get('p95_ms', 0)):.3f}  "
          f"p99={float(f.get('p99_ms', 0)):.3f}  max={float(f.get('max_ms', 0)):.3f} ms")
    sys.exit(0)

# Fallback: per-flow lines (small runs, or the NIC in-app [DIAG] TTFB channel).
vals = []
for line in lines:
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
# LOAD_PARALLEL total parallel TCP connections, spread across LOAD_PORTS
# contiguous server ports ([port .. port+LOAD_PORTS-1]), via
# experiments/nodes/loadgen.py — an asyncio (epoll-driven, single-thread)
# event-driven load generator. Replaces iperf2's -P N, which spawns N OS
# threads inside one process (25000 pthreads at 100k/4-ports is not viable at
# any instance size — see roadmap.md #20 scope item A / capacity-model.md).
# Sets globals: CLIENT_STDOUT, CLIENT_STDERR
run_ttfb_measurement() {
    local client_iid="$1" server_ip="$2" port="$3" count="$4" repo="$5"
    local timeout="${6:-${LOAD_TIMEOUT:-1800}}" label="${7:-Client}"
    local parallel="${LOAD_PARALLEL:-100000}"
    local nports="${LOAD_PORTS:-1}"
    [[ "$nports" -lt 1 ]] && nports=1
    local nbytes="${LOAD_BYTES:-1024}"
    local rate="${LOAD_RATE:-2000}"
    local conc="${LOAD_CONCURRENCY:-2000}"
    # Client think time between connect() and the first write. 0 = HTTP-style
    # send-immediately, the workload 0-RTT targets. Sweep with run_think_sweep.sh.
    local think="${LOAD_THINK_MS:-0}"

    # Pacing sets a wall-clock FLOOR the transport timeout must clear: at
    # LOAD_RATE conn/s a round cannot finish sooner than parallel/rate seconds,
    # before any transfer or teardown. A timeout tuned for the old burst shape
    # would abort a correctly-paced run partway through and report it as a
    # client failure, so say so up front rather than after 30 minutes.
    # rate may be fractional, so do the arithmetic in python (bc is not installed
    # on the Amazon Linux AMI); floor=0 signals "unpaced" back to the shell.
    local floor
    floor=$(python3 -c "r=float('$rate'); print(int($parallel/r*$count) if r>0 else 0)" 2>/dev/null || echo 0)
    if (( floor > 0 )); then
        log "Arrival pacing: ${rate} conn/s x $parallel conns x $count round(s) — minimum ${floor}s of spawn time"
        if (( floor > timeout )); then
            warn "LOAD_TIMEOUT=${timeout}s is below the ${floor}s pacing floor — raise LOAD_TIMEOUT or LOAD_RATE, or the round will be cut off mid-run"
        fi
    else
        warn "LOAD_RATE=0 — connections arrive as one burst. This is a stress/capacity run; its latency numbers include SYN queueing and must not be read as 0-RTT latency results."
    fi

    local result
    result=$(ssm_run "$client_iid" \
        "command -v python3 >/dev/null || { echo 'ERROR: python3 not installed'; exit 1; }
         ulimit -n 1048576 2>/dev/null || true
         success=0
         for i in \$(seq 1 $count); do
             echo \"--- Round \$i/$count: $nports port(s) starting at $port x $parallel total connections, $nbytes bytes/conn, ${rate} conn/s arrival, ${think}ms think, max $conc in flight ---\"
             python3 $repo/experiments/nodes/loadgen.py --mode client --host $server_ip --port $port --port-count $nports --parallel $parallel --bytes $nbytes --rate $rate --think-ms $think --concurrency-limit $conc && success=\$((success + 1))
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
        warn "$label: partial success — see client output above"
    else
        fail "$label: all $count connection(s) failed"
    fi
}
