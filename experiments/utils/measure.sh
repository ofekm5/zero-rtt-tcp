#!/usr/bin/env bash
# Shared measurement helpers for experiment orchestrators.
# Source after ssm.sh. Requires: ssm_run, json_idx, pass, fail, warn.
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
# Runs <count> sequential iperf flows on the client VM via SSM.
# Sets globals: CLIENT_STDOUT, CLIENT_STDERR
run_ttfb_measurement() {
    local client_iid="$1" server_ip="$2" port="$3" count="$4" repo="$5"
    local timeout="${6:-120}" label="${7:-Client}"

    local result
    result=$(ssm_run "$client_iid" \
        "command -v iperf >/dev/null || { echo 'ERROR: iperf not installed'; exit 1; }
         success=0
         for i in \$(seq 1 $count); do
             echo \"--- Connection \$i/$count ---\"
             out=\$(iperf -c $server_ip -p $port -n 1M -f m 2>&1)
             echo \"\$out\"
             echo \"\$out\" | grep -q 'bits/sec' && success=\$((success + 1))
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
