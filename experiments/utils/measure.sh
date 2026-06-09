#!/usr/bin/env bash
# Shared measurement helpers for experiment orchestrators.
# Source after ssm.sh. Requires: ssm_run, json_idx, pass, fail, warn.
#
# Measurement points (all intra-host intervals — no cross-machine clock sync):
#   - ClientNIC TTFB: stamped in clientnic-dpdk-forwarder (SYN ingress → 1st s2c data byte)
#   - ServerNIC TTFB: stamped in servernic-dpdk        (SYN ingress → 1st s2c data byte)
# Each NIC source emits: "[METRIC] <ttfb|fct> node=<n> flow=... <us|ms>=<v>"

# summarize_metric <metric> <node> <label>
# Reads text on stdin, extracts all matching [METRIC] samples, prints count +
# min/mean/median/max in ms (us values are normalised to ms). No-op if none found.
# stdin is consumed into an env var so the heredoc can supply the Python script.
summarize_metric() {
    local metric="$1" node="$2" label="$3" data
    data="$(cat)"
    METRIC_DATA="$data" python3 - "$metric" "$node" "$label" <<'PY'
import os, sys, re, statistics
metric, node, label = sys.argv[1], sys.argv[2], sys.argv[3]
pat = re.compile(r'\[METRIC\]\s+%s\s+node=%s\b.*?(us|ms)=([0-9.]+)'
                 % (re.escape(metric), re.escape(node)))
vals = []
for line in os.environ.get("METRIC_DATA", "").splitlines():
    m = pat.search(line)
    if not m:
        continue
    v = float(m.group(2))
    if m.group(1) == 'us':
        v /= 1000.0
    vals.append(v)
if not vals:
    print(f"  {label}: no samples found")
    sys.exit(0)
print(f"  {label}: n={len(vals)}  "
      f"min={min(vals):.3f}  mean={statistics.mean(vals):.3f}  "
      f"median={statistics.median(vals):.3f}  max={max(vals):.3f} ms")
PY
}

# report_nic_ttfb <log-text> <node>
# Convenience wrapper: summarise a NIC's per-flow TTFB from its captured log blob.
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
        "command -v iperf3 >/dev/null || { echo 'ERROR: iperf3 not installed'; exit 1; }
         success=0
         for i in \$(seq 1 $count); do
             echo \"--- Connection \$i/$count ---\"
             out=\$(iperf3 -c $server_ip -p $port -n 1M -f m 2>&1)
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
