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
# Sources experiments/utils/endpoint.sh itself: endpoint tuning, capture and
# analysis are shared verbatim with the plain-TCP baseline so the two stacks
# differ only in the data plane under test.
#
# Optional:
#   REMOTE_OUTPUT_CAP — byte ceiling this transport imposes on remote_stdout
#                       (SSM: 24000). Unset/0 means uncapped (SSH).
#
# Usage:
#   source "$(dirname "$0")/../utils/run_core.sh"
#   run_experiment <servernic_eth1_mac> <clientnic_eth1_mac> <server_eth0_mac> \
#                  <clientnic_eth2_mac> <servernic_eth2_mac>

# shellcheck source=./endpoint.sh
source "$(dirname "${BASH_SOURCE[0]}")/endpoint.sh"

# warn_if_truncated <text> <label>
# The transport's output cap is silent — a fetched blob that lands at the ceiling
# is a prefix, not the whole file, and every grep/count run against it is scoped
# to that prefix. Say so, loudly, instead of reporting statistics over a fragment.
warn_if_truncated() {
    local text="$1" label="$2" size
    [[ "${REMOTE_OUTPUT_CAP:-0}" -gt 0 ]] || return 0
    size=${#text}
    # Within 512 bytes of the cap: treat as truncated. The cap trims mid-line, so
    # an exact match is not guaranteed.
    if (( size >= REMOTE_OUTPUT_CAP - 512 )); then
        warn "$label: fetched ${size} bytes, at this transport's ${REMOTE_OUTPUT_CAP}-byte output cap — content is TRUNCATED. Counts and greps below cover only the captured prefix. Read the full file on the node."
    fi
}

# run_experiment <servernic_eth1_mac> <clientnic_eth1_mac> <server_eth0_mac>
#                <clientnic_eth2_mac> <servernic_eth2_mac>
#
# All five MACs must be resolved by the caller (transport-specific) before calling.
# Each SmartNIC needs both its PEER MACs (TX destinations) and its OWN two DPDK
# port MACs — the binaries map port role by MAC, since DPDK port IDs follow PCI
# enumeration order rather than ENI device_index. Note the first three double up:
# each NIC's eth1 MAC is the other's gateway, and its own DPDK port identity.
run_experiment() {
    local GW_MAC="$1"                 # ServerNIC eth1: ClientNIC's --gw-mac, ServerNIC's own client-facing port
    local CLIENTNIC_ETH1_MAC="$2"     # ClientNIC eth1: ServerNIC's --gw-mac, ClientNIC's own server-facing port
    local SERVER_ETH0_MAC="$3"        # Server eth0:    ServerNIC's --server-mac
    local CLIENTNIC_ETH2_MAC="$4"     # ClientNIC eth2: ClientNIC's own client-facing port
    local SERVERNIC_ETH2_MAC="$5"     # ServerNIC eth2: ServerNIC's own server-facing port

    # Port range the load is spread across (see measure.sh LOAD_PORTS). The data
    # plane (clientnic-dpdk-forwarder + servernic-dpdk) is told to cover the same
    # range via --port-count; endpoint captures filter the same range.
    local NPORTS="${LOAD_PORTS:-1}"
    [[ "$NPORTS" -lt 1 ]] && NPORTS=1
    local PORT_HI=$(( SERVER_PORT + NPORTS - 1 ))
    local BPF_PORTS="portrange ${SERVER_PORT}-${PORT_HI}"
    log "Load/port plan: $NPORTS port(s) [${SERVER_PORT}-${PORT_HI}], LOAD_PARALLEL=${LOAD_PARALLEL:-100000}, LOAD_BYTES=${LOAD_BYTES:-1024}, LOAD_RATE=${LOAD_RATE:-2000} conn/s, LOAD_CONCURRENCY=${LOAD_CONCURRENCY:-2000}"

    # ─── Port-space assertion (capacity-model.md §8) ──────────────────────────
    # run_core.sh widens the client's ephemeral range to 1024-65535 below, so
    # the available range is ~64512. Assert LOAD_PORTS * range >= target
    # connections *before* spending 10+ minutes on a run that can't possibly
    # open that many sockets from one source IP, with 2xMSL TIME_WAIT margin
    # (halve the raw range as a safety factor for in-flight TIME_WAIT reuse).
    local TARGET_CONNS="${LOAD_PARALLEL:-100000}"
    local EPHEMERAL_RANGE=64512
    local USABLE_RANGE=$(( EPHEMERAL_RANGE / 2 ))
    local PORT_SPACE=$(( NPORTS * USABLE_RANGE ))
    if (( PORT_SPACE < TARGET_CONNS )); then
        fail "Port-space check: LOAD_PORTS=$NPORTS x usable_range=$USABLE_RANGE = $PORT_SPACE" \
             " < LOAD_PARALLEL=$TARGET_CONNS — raise LOAD_PORTS before running"
        return 1
    else
        pass "Port-space check: $NPORTS port(s) x $USABLE_RANGE usable range = $PORT_SPACE >= $TARGET_CONNS target"
    fi

    # ─── Pull latest code (clone if missing) ──────────────────────────────────
    # On a fresh stack the CDK user-data clone can fail (e.g. expired token),
    # leaving VMs with no repo. Clone-on-demand here using the GitHub PAT from
    # Secrets Manager (nanoclaw/github-token) so the run is self-healing.
    #
    # REPO_REF selects which ref the VMs run. It defaults to main, so normal runs
    # are unchanged — but a harness change cannot be validated on real infra
    # before it is merged unless the VMs can be pointed at its branch, and
    # merging unexercised measurement code to main is the wrong order.
    local ref="${REPO_REF:-main}"
    log "Syncing all VMs to origin/${ref} (cloning if missing)..."
    [[ "$ref" != "main" ]] && warn "REPO_REF=${ref} — VMs are running a NON-MAIN ref"
    for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
        remote_bg "$iid" \
            "git config --global --add safe.directory $REPO_PATH 2>/dev/null || true; \
             if [ -d $REPO_PATH/.git ]; then \
                 sudo -u ec2-user git -C $REPO_PATH fetch origin $ref 2>&1 && \
                 sudo -u ec2-user git -C $REPO_PATH reset --hard origin/$ref 2>&1 || true; \
             else \
                 GITHUB_TOKEN=\$(aws secretsmanager get-secret-value --secret-id nanoclaw/github-token --query SecretString --output text --region eu-central-1 | tr -d '\"'); \
                 sudo -u ec2-user git clone \"https://x-access-token:\${GITHUB_TOKEN}@github.com/ofekm5/zero-rtt-tcp.git\" $REPO_PATH 2>&1 || true; \
                 sudo -u ec2-user git -C $REPO_PATH checkout $ref 2>&1 || true; \
                 chown -R ec2-user:ec2-user $REPO_PATH 2>/dev/null || true; \
             fi"
    done
    sleep 20

    # Confirm the VMs actually landed on the requested ref. A failed fetch is
    # swallowed by `|| true` above (deliberately — a stale checkout beats an
    # aborted run), so without this check the run would silently measure
    # whatever code the VM happened to already have.
    local vm_head
    for iid in "$SERVER_ID" "$SERVERNIC_ID" "$CLIENTNIC_ID" "$CLIENT_ID"; do
        vm_head=$(remote_stdout "$iid" \
            "git -C $REPO_PATH rev-parse --short HEAD 2>/dev/null || echo NOREPO" 30)
        log "  $iid HEAD: $(echo "$vm_head" | tr -d '[:space:]')"
    done

    # ─── Endpoint tuning (shared with the baseline stack) ─────────────────────
    # sysctls, MTU, offloads and netem all live in experiments/utils/endpoint.sh
    # so the baseline runs byte-identical setup — see that file's header for why
    # the emulated RTT sits entirely on the Server's egress.
    endpoint_tune "$CLIENT_ID" "$SERVER_ID"

    # ─── Cleanup any leftover processes ───────────────────────────────────────
    log "Cleaning up previous runs..."
    remote_bg "$SERVER_ID" \
        "pkill -9 -f loadgen.py 2>/dev/null; conntrack -F 2>/dev/null || true; rm -f /tmp/server.log"
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
         cd $REPO_PATH/src/clientnic/dpdk-forwarder; \
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
         cd $REPO_PATH/src/servernic/dpdk; \
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
    log "Step 1: Starting Server via node script ($NPORTS load-generator port(s))..."
    remote_bg "$SERVER_ID" \
        "LOAD_PORTS=$NPORTS REPO_REF=$ref setsid bash $REPO_PATH/experiments/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &"
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
         CLIENT_PORT_MAC=$GW_MAC SERVER_PORT_MAC=$SERVERNIC_ETH2_MAC REPO_REF=$ref \
         setsid bash $REPO_PATH/experiments/dpdk/servernic.sh \
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
        warn_if_truncated "$SERVERNIC_LOG_EARLY" "ServerNIC early log (/tmp/servernic.log)"
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
        "SKIP_BUILD=1 PORT_COUNT=$NPORTS REPO_REF=$ref \
         CLIENT_PORT_MAC=$CLIENTNIC_ETH2_MAC SERVER_PORT_MAC=$CLIENTNIC_ETH1_MAC \
         setsid bash $REPO_PATH/experiments/dpdk/clientnic.sh $GW_MAC \
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
    endpoint_capture_start "$CLIENT_ID" "$SERVER_ID" "$BPF_PORTS"

    # ─── Step 4: Run client test ──────────────────────────────────────────────
    log "Step 4: Running client test ($CONNECTIONS connection(s))..."
    run_ttfb_measurement "$CLIENT_ID" "$SERVER_IP" "$SERVER_PORT" \
        "$CONNECTIONS" "$REPO_PATH" "${LOAD_TIMEOUT:-1800}"

    sleep 3

    # ─── Step 5: Stop captures and binaries ───────────────────────────────────
    log "Step 5: Stopping packet captures and DPDK binaries..."
    endpoint_capture_stop "$CLIENT_ID" "$SERVER_ID"
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
    warn_if_truncated "$SERVER_LOG" "Server log (/tmp/server.log)"
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
    warn_if_truncated "$SERVERNIC_LOG" "ServerNIC log (/tmp/servernic.log)"
    echo "--- ServerNIC log ---"
    echo "$SERVERNIC_LOG"
    echo "---------------------"

    CLIENTNIC_LOG=$(remote_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic.log" 30)
    warn_if_truncated "$CLIENTNIC_LOG" "ClientNIC log (/tmp/clientnic.log)"
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
    # Sets ENDPOINT_METRICS. Shared with the baseline stack — see endpoint.sh.
    log "Packet analysis: analyzing each endpoint capture on its own host..."
    endpoint_analyze "$CLIENT_ID" "$SERVER_ID" "$REPO_PATH"

    # ─── Latency metrics ──────────────────────────────────────────────────────
    # send_unlock leads; FCT and server_gap are explicitly demoted to secondary.
    # The old summary also piped $CLIENT_STDOUT through summarize_metric for
    # "ttfb" and "fct" — but loadgen.py emits no metric= lines at all, so those
    # two rows printed "no samples found" on every run since the iperf→loadgen
    # migration. Removed rather than left to read as missing data.
    log "Latency metrics: aggregating NIC in-app TTFB + endpoint pcap metrics..."
    local METRICS_SUMMARY
    METRICS_SUMMARY=$(
        endpoint_latency_summary "${ENDPOINT_METRICS:-}"
        echo "  ── Data-plane internal (in-app rdtsc, not client-observed) ──"
        report_nic_ttfb "$CLIENTNIC_LOG" "clientnic"
        report_nic_ttfb "$SERVERNIC_LOG" "servernic"
    )
    echo "--- Latency summary ---"
    echo "$METRICS_SUMMARY"
    echo "-----------------------"

    # A capacity run's latency figures are not 0-RTT results — say so here, in
    # the run output, rather than relying on whoever reads the report to recall
    # which knobs were set. See experiments/dpdk/run_stress.sh.
    if [[ "${LOAD_RATE:-2000}" == "0" ]]; then
        warn "CAPACITY RUN (LOAD_RATE=0): the latency block above includes SYN queueing behind the whole burst. Valid readings from this run: establishment success rate and data-plane throughput. NOT valid: any 0-RTT latency claim."
    fi

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
