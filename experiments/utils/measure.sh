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
IPERF_PARALLEL="${IPERF_PARALLEL:-100000}"
IPERF_PORTS="${IPERF_PORTS:-4}"
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
# contiguous server ports ([port .. port+IPERF_PORTS-1]) — one iperf2 process per
# port, each with -P (IPERF_PARALLEL / IPERF_PORTS). Spreading across multiple
# destination ports multiplies the ephemeral-port space so the client can actually
# open 100000 connections from a single source IP.
# Load generator is iperf2 ONLY — an iperf3 binary shadowing `iperf` is rejected.
# Sets globals: CLIENT_STDOUT, CLIENT_STDERR
run_ttfb_measurement() {
    local client_iid="$1" server_ip="$2" port="$3" count="$4" repo="$5"
    local timeout="${6:-120}" label="${7:-Client}"
    local parallel="${IPERF_PARALLEL:-100000}"
    local nports="${IPERF_PORTS:-1}"
    [[ "$nports" -lt 1 ]] && nports=1
    local base="$port"
    local hi=$(( base + nports - 1 ))
    local perport=$(( (parallel + nports - 1) / nports ))   # ceil(parallel/nports)
    local plist="" p
    for (( p=base; p<=hi; p++ )); do plist="$plist $p"; done
    plist="${plist# }"

    local result
    result=$(ssm_run "$client_iid" \
        "command -v iperf >/dev/null || { echo 'ERROR: iperf not installed'; exit 1; }
         if iperf --version 2>&1 | grep -qiE 'iperf[ ]?3'; then
             echo 'ERROR: iperf3 detected — this experiment requires iperf2'; exit 1
         fi
         ulimit -n $((perport + 1024)) 2>/dev/null || true
         success=0
         for i in \$(seq 1 $count); do
             echo \"--- Round \$i/$count: $nports port(s) [$base-$hi] x $perport parallel = $((perport * nports)) conns ---\"
             rm -f /tmp/iperf_round.*.out
             pids=\"\"
             for p in $plist; do
                 iperf -c $server_ip -p \$p -P $perport -n 1M -f m > /tmp/iperf_round.\$p.out 2>&1 &
                 pids=\"\$pids \$!\"
             done
             wait \$pids 2>/dev/null
             ok=0
             for p in $plist; do
                 cat /tmp/iperf_round.\$p.out
                 grep -q 'bits/sec' /tmp/iperf_round.\$p.out && ok=\$((ok + 1))
             done
             [ \$ok -eq $nports ] && success=\$((success + 1))
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
