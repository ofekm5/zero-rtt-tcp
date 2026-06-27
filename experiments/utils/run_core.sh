#!/usr/bin/env bash
# Shared runner core for the 0-RTT TCP experiment.
#
# Transport-agnostic orchestration: define the following before sourcing this file
# (or source a transport layer that defines them):
#
#   remote_run  <node-id> <command> [timeout-sec]
#     → Runs command synchronously; returns JSON [Status, Stdout, Stderr] or
#       a transport-equivalent structured result.  Sets globals used by json_idx.
#   remote_bg   <node-id> <command>
#     → Fires command in background, returns immediately.
#   remote_stdout <node-id> <command> [timeout-sec]
#     → Returns only stdout of command.
#   discover_nodes
#     → Populates: SERVER_ID SERVERNIC_ID CLIENTNIC_ID CLIENT_ID SERVER_IP
#   log  <message>
#   pass <message>
#   fail <message>
#   warn <message>
#
# Also requires:
#   - source experiments/utils/measure.sh  (before sourcing run_core.sh)
#   - REPO_PATH, SERVER_PORT, CONNECTIONS, FAILURES set by caller
#
# Usage:
#   source "$(dirname "$0")/../utils/run_core.sh"
#   run_experiment  <gw_mac> <clientnic_eth1_mac> <server_eth0_mac>

# run_experiment <gw_mac> <clientnic_eth1_mac> <server_eth0_mac>
# All three MACs must be resolved by the caller (transport-specific) before calling.
run_experiment() {
    local GW_MAC="$1"
    local CLIENTNIC_ETH1_MAC="$2"
    local SERVER_ETH0_MAC="$3"

    # Port range the load is spread across (see measure.sh IPERF_PORTS). The data
    # plane (clientnic-dpdk-forwarder + servernic-dpdk) is told to cover the same
    # range via --port-count; endpoint captures filter the same range.
    local NPORTS="${IPERF_PORTS:-1}"
    [[ "$NPORTS" -lt 1 ]] && NPORTS=1
    local PORT_HI=$(( SERVER_PORT + NPORTS - 1 ))
    local BPF_PORTS="portrange ${SERVER_PORT}-${PORT_HI}"
    log "Load/port plan: $NPORTS port(s) [${SERVER_PORT}-${PORT_HI}], IPERF_PARALLEL=${IPERF_PARALLEL:-100000}"

    # ─── Pull latest code (clone if missing) ──────────────────────────────────
    # On a fresh stack the CDK user-data clone can fail (e.g. expired token),
    # leaving VMs with no repo. Clone-on-demand here using the GitHub PAT from
    # Secrets Manager (nanoclaw/github-token) so the run is self-healing.
    log "Pulling latest code on all VMs (cloning if missing)..."
    for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
        remote_bg "$iid" \
            "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; \
             if [ -d $REPO_PATH/.git ]; then \
                 sudo -u ec2-user git -C $REPO_PATH pull origin main 2>&1 || true; \
             else \
                 GITHUB_TOKEN=\$(aws secretsmanager get-secret-value --secret-id nanoclaw/github-token --query SecretString --output text --region eu-central-1 | tr -d '\"'); \
                 sudo -u ec2-user git clone \"https://x-access-token:\${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-demo.git\" $REPO_PATH 2>&1 || true; \
                 chown -R ec2-user:ec2-user $REPO_PATH 2>/dev/null || true; \
             fi"
    done
    sleep 20

    # ─── Disable TCP options on Client + Server ───────────────────────────────
    log "Disabling TCP timestamps/window-scaling/SACK on Client and Server..."
    remote_bg "$CLIENT_ID" \
        "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0"
    remote_bg "$SERVER_ID" \
        "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0"
    sleep 2

    # ─── Accuracy knobs: offload-off + netem on endpoint NICs ─────────────────
    log "Accuracy knobs: disabling GRO/LRO/TSO/GSO on Client and Server NICs..."
    remote_bg "$CLIENT_ID" \
        "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"
    remote_bg "$SERVER_ID" \
        "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"

    log "Accuracy knobs: applying tc netem 50ms delay on Client and Server egress..."
    # netem default queue limit is 1000 pkts; at ~100ms RTT a window's worth of
    # 100 parallel flows exceeds that and tail-drops, manufacturing loss. Raise
    # the limit so netem emulates pure delay, not delay+loss.
    remote_bg "$CLIENT_ID" \
        "tc qdisc del dev eth0 root 2>/dev/null || true; \
         tc qdisc add dev eth0 root netem delay 50ms limit 1000000 2>/dev/null || true"
    remote_bg "$SERVER_ID" \
        "tc qdisc del dev eth0 root 2>/dev/null || true; \
         tc qdisc add dev eth0 root netem delay 50ms limit 1000000 2>/dev/null || true"
    sleep 2

    # ─── Cleanup any leftover processes ───────────────────────────────────────
    log "Cleaning up previous runs..."
    remote_bg "$SERVER_ID" \
        "pkill -9 -f iperf 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log"
    remote_bg "$SERVERNIC_ID" \
        "pkill -x servernic-dpdk 2>/dev/null; pkill -f 'servernic/scapy' 2>/dev/null; \
         rm -f /tmp/servernic.log; iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null"
    remote_run "$CLIENTNIC_ID" \
        "pkill -f clientnic-dpdk-forwarder 2>/dev/null; pkill -f clientnic-dpdk 2>/dev/null; \
         pkill tcpdump 2>/dev/null; sleep 5; \
         pkill -9 -f clientnic-dpdk-forwarder 2>/dev/null; sleep 2; \
         rm -rf /var/run/dpdk/rte/ 2>/dev/null; \
         rm -f /tmp/clientnic.log /tmp/client_side.pcap /tmp/validate_0rtt.py; \
         iptables -F FORWARD 2>/dev/null; echo CLEANUP_DONE" \
        30 > /dev/null
    sleep 5

    # ─── Build: clientnic-dpdk-forwarder ──────────────────────────────────────
    log "Build: Building clientnic-dpdk-forwarder on ClientNIC VM..."

    local BUILD_RESULT BUILD_STATUS BUILD_STDOUT BUILD_STDERR
    BUILD_RESULT=$(remote_run "$CLIENTNIC_ID" \
        "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; \
         cd $REPO_PATH/clientnic/dpdk-forwarder; \
         rm -rf builddir; \
         /usr/local/bin/meson setup builddir 2>&1 && \
         cd builddir && /usr/local/bin/ninja 2>&1 && \
         echo 'BUILD_SUCCESS'" \
        600)

    BUILD_STATUS=$(echo "$BUILD_RESULT" | json_idx 0)
    BUILD_STDOUT=$(echo "$BUILD_RESULT" | json_idx 1)
    BUILD_STDERR=$(echo "$BUILD_RESULT" | json_idx 2)

    echo "--- ClientNIC build output (last 20 lines) ---"
    echo "$BUILD_STDOUT" | tail -20
    [[ -n "$BUILD_STDERR" ]] && echo "stderr: $BUILD_STDERR" | tail -10
    echo "----------------------------------------------"

    if echo "$BUILD_STDOUT" | grep -q "BUILD_SUCCESS"; then
        pass "Build: clientnic-dpdk-forwarder meson + ninja build succeeded"
    else
        fail "Build: clientnic-dpdk-forwarder build failed (status=$BUILD_STATUS)"
        echo "Full build output:"
        echo "$BUILD_STDOUT"
    fi

    # ─── Build: servernic-dpdk ────────────────────────────────────────────────
    log "Build: Building servernic-dpdk on ServerNIC VM..."

    local SERVERNIC_BUILD_RESULT SERVERNIC_BUILD_STATUS SERVERNIC_BUILD_STDOUT
    SERVERNIC_BUILD_RESULT=$(remote_run "$SERVERNIC_ID" \
        "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig; \
         cd $REPO_PATH/servernic/dpdk; \
         rm -rf builddir; \
         /usr/local/bin/meson setup builddir 2>&1 && \
         cd builddir && /usr/local/bin/ninja 2>&1 && \
         echo 'BUILD_SUCCESS'" \
        600)

    SERVERNIC_BUILD_STATUS=$(echo "$SERVERNIC_BUILD_RESULT" | json_idx 0)
    SERVERNIC_BUILD_STDOUT=$(echo "$SERVERNIC_BUILD_RESULT" | json_idx 1)

    echo "--- ServerNIC build output (last 20 lines) ---"
    echo "$SERVERNIC_BUILD_STDOUT" | tail -20
    echo "----------------------------------------------"

    if echo "$SERVERNIC_BUILD_STDOUT" | grep -q "BUILD_SUCCESS"; then
        pass "Build: servernic-dpdk meson + ninja build succeeded"
    else
        fail "Build: servernic-dpdk build failed (status=$SERVERNIC_BUILD_STATUS)"
        echo "Full build output:"
        echo "$SERVERNIC_BUILD_STDOUT"
    fi

    # ─── Step 1: Start Server ─────────────────────────────────────────────────
    log "Step 1: Starting Server via node script ($NPORTS iperf port(s))..."
    remote_bg "$SERVER_ID" \
        "IPERF_PORTS=$NPORTS setsid bash $REPO_PATH/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
    sleep 3

    local LISTEN_CHECK
    LISTEN_CHECK=$(remote_stdout "$SERVER_ID" \
        "ss -tlnp | grep $SERVER_PORT && echo LISTENING || echo NOT_LISTENING" 30)
    if echo "$LISTEN_CHECK" | grep -q "LISTENING"; then
        pass "Server listening on :$SERVER_PORT"
    else
        fail "Server not listening on :$SERVER_PORT"
        echo "  ss output: $LISTEN_CHECK"
    fi

    # ─── Step 2: Start ServerNIC (DPDK binary) ───────────────────────────────
    log "Step 2: Starting ServerNIC DPDK binary via node script..."
    remote_bg "$SERVERNIC_ID" \
        "SKIP_BUILD=1 PORT_COUNT=$NPORTS CLIENTNIC_GW_MAC=$CLIENTNIC_ETH1_MAC SERVER_GW_MAC=$SERVER_ETH0_MAC \
         MIDDLE_ENI_MAC=$GW_MAC setsid bash $REPO_PATH/experiments/dpdk/servernic.sh \
         < /dev/null >> /tmp/servernic.log 2>&1 &"
    sleep 5

    local SERVERNIC_RUNNING
    SERVERNIC_RUNNING=$(remote_stdout "$SERVERNIC_ID" \
        "pgrep -f servernic-dpdk && echo RUNNING || echo NOT_RUNNING" 30)
    if echo "$SERVERNIC_RUNNING" | grep -q "RUNNING"; then
        pass "ServerNIC: servernic-dpdk process is running"
    else
        fail "ServerNIC: servernic-dpdk process not found — startup failed"
        local SERVERNIC_LOG_EARLY
        SERVERNIC_LOG_EARLY=$(remote_stdout "$SERVERNIC_ID" \
            "cat /tmp/servernic.log 2>/dev/null || echo '(no log)'" 30)
        echo "--- ServerNIC early log ---"
        echo "$SERVERNIC_LOG_EARLY"
        echo "---------------------------"
    fi

    local FWRD
    FWRD=$(remote_stdout "$SERVERNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
    if [[ "$FWRD" == "1" ]]; then
        pass "ServerNIC: IP forwarding enabled"
    else
        fail "ServerNIC: IP forwarding NOT enabled (got '$FWRD')"
    fi

    # ─── Step 3: Start ClientNIC (dpdk-forwarder) ─────────────────────────────
    log "Step 3: Starting ClientNIC (dpdk-forwarder) via node script..."
    remote_bg "$CLIENTNIC_ID" \
        "iptables -F FORWARD 2>/dev/null; iptables -F OUTPUT 2>/dev/null || true"
    sleep 1

    remote_bg "$CLIENTNIC_ID" \
        "SKIP_BUILD=1 PORT_COUNT=$NPORTS setsid bash $REPO_PATH/experiments/dpdk/clientnic.sh $GW_MAC \
         < /dev/null >> /tmp/clientnic.log 2>&1 &"
    sleep 5

    FWRD=$(remote_stdout "$CLIENTNIC_ID" "cat /proc/sys/net/ipv4/ip_forward" 30)
    if [[ "$FWRD" == "1" ]]; then
        pass "ClientNIC: IP forwarding enabled"
    else
        fail "ClientNIC: IP forwarding NOT enabled"
    fi

    local DPDK_RUNNING
    DPDK_RUNNING=$(remote_stdout "$CLIENTNIC_ID" \
        "pgrep -f clientnic-dpdk-forwarder && echo RUNNING || echo NOT_RUNNING" 30)
    if echo "$DPDK_RUNNING" | grep -q "RUNNING"; then
        pass "Step 3: clientnic-dpdk-forwarder process is running"
    else
        fail "Step 3: clientnic-dpdk-forwarder process not found — startup failed"
        local DPDK_LOG
        DPDK_LOG=$(remote_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
        echo "--- ClientNIC forwarder log ---"
        echo "$DPDK_LOG"
        echo "-------------------------------"
    fi

    # ─── Step 3b: Start endpoint captures ────────────────────────────────────
    log "Step 3b: Starting endpoint tcpdump captures (Client host + Server host)..."
    remote_run "$CLIENT_ID" \
        "pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap" 30 > /dev/null
    remote_run "$SERVER_ID" \
        "pkill tcpdump 2>/dev/null || true; rm -f /tmp/server_side.pcap" 30 > /dev/null

    _hiprec_start() {
        local iid="$1" iface="$2" filter="$3" outfile="$4"
        remote_bg "$iid" "
if tcpdump --time-stamp-precision=nano -d -i lo 2>/dev/null | grep -q .; then
    HIPREC_FLAG='--time-stamp-precision=nano'
elif tcpdump -j adapter -d -i lo 2>/dev/null | grep -q .; then
    HIPREC_FLAG='-j adapter'
else
    HIPREC_FLAG=''
fi
tcpdump \$HIPREC_FLAG -i $iface -nn -s 128 '$filter' -w $outfile </dev/null >/tmp/tcpdump_hiprec.log 2>&1 &
"
    }

    _hiprec_start "$CLIENT_ID" "eth0" "tcp $BPF_PORTS" "/tmp/client_side.pcap"
    _hiprec_start "$SERVER_ID" "eth0" "tcp $BPF_PORTS" "/tmp/server_side.pcap"
    sleep 2

    # ─── Step 4: Run client test ──────────────────────────────────────────────
    log "Step 4: Running client test ($CONNECTIONS connection(s))..."
    run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" \
        "$CONNECTIONS" "$REPO_PATH" "${IPERF_TIMEOUT:-1800}"

    sleep 3

    # ─── Step 5: Stop captures and binaries ───────────────────────────────────
    log "Step 5: Stopping packet captures and DPDK binaries..."
    remote_run "$CLIENT_ID"   "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
    remote_run "$SERVER_ID"   "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
    remote_run "$CLIENTNIC_ID" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
    remote_run "$CLIENTNIC_ID" \
        "pkill -f clientnic-dpdk-forwarder 2>/dev/null || true; sleep 2" 30 > /dev/null
    remote_run "$SERVERNIC_ID" \
        "pkill -f servernic-dpdk 2>/dev/null || true; sleep 2" 30 > /dev/null
    pass "Captures stopped, DPDK binaries signalled"

    # ─── Step 6: Verify server received data ──────────────────────────────────
    log "Step 6: Verifying server received data..."
    local SERVER_LOG
    SERVER_LOG=$(remote_stdout "$SERVER_ID" "cat /tmp/server.log" 30)
    echo "--- Server log ---"
    echo "$SERVER_LOG"
    echo "------------------"

    if echo "$SERVER_LOG" | grep -qiE "Received|bytes"; then
        pass "Server received data from client"
    else
        fail "Server log shows no received data"
    fi

    # ─── Step 7: Collect and check per-VM logs ────────────────────────────────
    log "Step 7: Collecting per-VM logs..."

    local SERVERNIC_LOG CLIENTNIC_LOG
    SERVERNIC_LOG=$(remote_stdout "$SERVERNIC_ID" \
        "cat /tmp/servernic.log 2>/dev/null || echo '(no log)'" 30)
    echo "--- ServerNIC log ---"
    echo "$SERVERNIC_LOG"
    echo "---------------------"

    CLIENTNIC_LOG=$(remote_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
    echo "--- ClientNIC DPDK log ---"
    echo "$CLIENTNIC_LOG"
    echo "--------------------------"

    if echo "$CLIENTNIC_LOG" | grep -qiE "flow created|spoofed SYN-ACK|SYN forwarded|V="; then
        pass "ClientNIC dpdk-forwarder: 0-RTT flow table activity confirmed"
    else
        fail "ClientNIC dpdk-forwarder: no flow table activity in log"
    fi

    if echo "$SERVERNIC_LOG" | grep -qiE "PENDING|delta|SYN-ACK.*drop|flush|V="; then
        pass "ServerNIC dpdk: translation activity confirmed"
    else
        warn "ServerNIC dpdk: no translation activity in log (may indicate no SYN-ACK received yet)"
    fi

    # ─── Packet capture analysis ──────────────────────────────────────────────
    log "Packet analysis: Collecting endpoint pcap sizes..."

    local CLIENT_PCAP_SIZE SERVER_PCAP_SIZE
    CLIENT_PCAP_SIZE=$(remote_stdout "$CLIENT_ID" \
        "ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'" 30)
    SERVER_PCAP_SIZE=$(remote_stdout "$SERVER_ID" \
        "ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'" 30)
    echo "  client_side.pcap: $CLIENT_PCAP_SIZE"
    echo "  server_side.pcap: $SERVER_PCAP_SIZE"

    # ─── Option A: analyze each large pcap on its own host ────────────────────
    # SSM caps StandardOutputContent at 24 KB and inline command params at 8 KB,
    # so the 20–40 MB endpoint pcaps cannot be shipped between hosts. Instead, run
    # analyze_metrics.py locally on the endpoint host that owns each capture and
    # collect only the small (~100 byte) key=value text output:
    #   • Client host eth0 capture (/tmp/client_side.pcap) → fct + send_unlock
    #   • Server host eth0 capture (/tmp/server_side.pcap) → server_gap
    # analyze_metrics.py streams `tcpdump -r` output (tcpdump already wrote these
    # captures, so it is always present) — O(flows) memory, parses 100k+ packets
    # in seconds, no heavy in-RAM pcap load.
    log "Packet analysis: Running client-side analysis on Client host capture..."
    local CLIENT_ANALYSIS_RESULT CLIENT_ANALYSIS_STATUS CLIENT_ANALYSIS_STDOUT CLIENT_ANALYSIS_STDERR
    CLIENT_ANALYSIS_RESULT=$(remote_run "$CLIENT_ID" \
        "python3 $REPO_PATH/experiments/utils/analyze_metrics.py \
            --client-pcap /tmp/client_side.pcap" \
        120)
    CLIENT_ANALYSIS_STATUS=$(echo "$CLIENT_ANALYSIS_RESULT" | json_idx 0)
    CLIENT_ANALYSIS_STDOUT=$(echo "$CLIENT_ANALYSIS_RESULT" | json_idx 1)
    CLIENT_ANALYSIS_STDERR=$(echo "$CLIENT_ANALYSIS_RESULT" | json_idx 2)

    log "Packet analysis: Running server-side analysis on Server host capture..."
    local SERVER_ANALYSIS_RESULT SERVER_ANALYSIS_STATUS SERVER_ANALYSIS_STDOUT SERVER_ANALYSIS_STDERR
    SERVER_ANALYSIS_RESULT=$(remote_run "$SERVER_ID" \
        "python3 $REPO_PATH/experiments/utils/analyze_metrics.py \
            --server-pcap /tmp/server_side.pcap" \
        120)
    SERVER_ANALYSIS_STATUS=$(echo "$SERVER_ANALYSIS_RESULT" | json_idx 0)
    SERVER_ANALYSIS_STDOUT=$(echo "$SERVER_ANALYSIS_RESULT" | json_idx 1)
    SERVER_ANALYSIS_STDERR=$(echo "$SERVER_ANALYSIS_RESULT" | json_idx 2)

    # Merge the two key=value outputs into one block for downstream summarizing.
    local ANALYSIS_STDOUT
    ANALYSIS_STDOUT=$(printf '%s\n%s' "$CLIENT_ANALYSIS_STDOUT" "$SERVER_ANALYSIS_STDOUT")

    echo "--- Endpoint metric analysis ---"
    echo "client (status: $CLIENT_ANALYSIS_STATUS):"
    echo "$CLIENT_ANALYSIS_STDOUT"
    [[ -n "$CLIENT_ANALYSIS_STDERR" ]] && echo "  stderr: $CLIENT_ANALYSIS_STDERR"
    echo "server (status: $SERVER_ANALYSIS_STATUS):"
    echo "$SERVER_ANALYSIS_STDOUT"
    [[ -n "$SERVER_ANALYSIS_STDERR" ]] && echo "  stderr: $SERVER_ANALYSIS_STDERR"
    echo "--------------------------------"

    if [[ "$CLIENT_ANALYSIS_STATUS" == "Success" && "$SERVER_ANALYSIS_STATUS" == "Success" ]] && \
       ! echo "$ANALYSIS_STDOUT" | grep -q "^missing="; then
        pass "Packet analysis: all endpoint metrics computed"
    else
        local NMISSING
        NMISSING=$(printf '%s' "$ANALYSIS_STDOUT" | grep -c '^missing=' || true)
        fail "Packet analysis: $NMISSING missing metric event(s) (client=$CLIENT_ANALYSIS_STATUS server=$SERVER_ANALYSIS_STATUS)"
    fi

    local ENDPOINT_METRICS="$ANALYSIS_STDOUT"

    # ─── Latency metrics ──────────────────────────────────────────────────────
    log "Latency metrics: aggregating TTFB + FCT + endpoint pcap metrics..."
    local METRICS_SUMMARY
    METRICS_SUMMARY=$(
        report_nic_ttfb "$CLIENTNIC_LOG" "clientnic"
        report_nic_ttfb "$SERVERNIC_LOG" "servernic"
        echo "$CLIENT_STDOUT" | summarize_metric "ttfb" "client" "Client TTFB   "
        echo "$CLIENT_STDOUT" | summarize_metric "fct"  "client" "Client FCT    "
        echo "${ENDPOINT_METRICS:-}" | summarize_metric "fct"         "client" "Pcap FCT      "
        echo "${ENDPOINT_METRICS:-}" | summarize_metric "send_unlock" "client" "Send unlock   "
        echo "${ENDPOINT_METRICS:-}" | summarize_metric "server_gap"  "server" "Server gap    "
    )
    echo "--- Latency summary ---"
    echo "$METRICS_SUMMARY"
    echo "-----------------------"

    if echo "$METRICS_SUMMARY" | grep -q "clientnic TTFB.*n=[1-9]"; then
        pass "Metrics: ClientNIC in-app TTFB samples collected"
    else
        warn "Metrics: no ClientNIC in-app TTFB samples (binary may predate instrumentation)"
    fi
    if echo "$METRICS_SUMMARY" | grep -q "servernic TTFB.*n=[1-9]"; then
        pass "Metrics: ServerNIC in-app TTFB samples collected"
    else
        warn "Metrics: no ServerNIC in-app TTFB samples (binary may predate instrumentation)"
    fi

    # Export for caller to use in reports
    CORE_METRICS_SUMMARY="$METRICS_SUMMARY"
    CORE_ENDPOINT_METRICS="$ENDPOINT_METRICS"
    CORE_SERVER_LOG="$SERVER_LOG"
    CORE_SERVERNIC_LOG="$SERVERNIC_LOG"
    CORE_CLIENTNIC_LOG="$CLIENTNIC_LOG"
}
