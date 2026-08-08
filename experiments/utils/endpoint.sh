#!/usr/bin/env bash
# Shared endpoint (Client VM + Server VM) setup, capture and analysis.
#
# Both the 0-RTT stack (experiments/utils/run_core.sh) and the plain-TCP
# baseline (experiments/baseline-tcp/run_experiment.sh) source this file, so the
# two runs are configured by the *same code* rather than by two copies that
# drift. That is the point: the project's central claim is a difference between
# the two stacks, so any endpoint parameter that differs between them —
# emulated latency, offloads, MTU, payload size, arrival rate, analyzer
# invocation — is a confound that shows up as 0-RTT benefit or cost.
# insights.md (2026-07-14) records one cross-comparison already invalidated this
# way, by mismatched tooling and transfer sizes.
#
# Requires from the caller (transport + logging shims):
#   remote_run, remote_bg, remote_stdout, json_idx, log, pass, fail, warn
#
# Knobs (override via env):
#   NETEM_RTT_MS : total emulated round-trip time in ms (default 100), applied
#                  on the ClientNIC<->ServerNIC leg — half per direction. The
#                  baseline stack gets it via wan_tune_middle_leg() (netem on
#                  kernel-routed NIC VMs); the DPDK stack via --wan-delay-us on
#                  both forwarders (wan_delay_us()). Endpoints stay clean and
#                  endpoint_tune() fails the run if they are not.
#   ANALYSIS_TIMEOUT : seconds allowed per endpoint analyzer run (default 600).

NETEM_RTT_MS="${NETEM_RTT_MS:-100}"

# endpoint_tune <client-iid> <server-iid>
#
# Applies every endpoint-side knob both stacks must share.
#
# NETEM PLACEMENT — this is a measurement correctness issue, not a detail.
# A `tc qdisc ... root netem delay` delays EGRESS only, so where the delay sits
# decides which metric can move. Two earlier placements were both wrong:
#     50/50 on both endpoints  → 0-RTT connect() paid the Client's own 50 ms
#                                egress before the spoof could return, so the
#                                measured saving was HALF the emulated RTT.
#     Full RTT on Server egress → `send_unlock` correct (2026-08-04: 100.835 →
#                                0.226 ms), but FCT gain structurally impossible
#                                (-0.09 ms): the real SYN-ACK is what ServerNIC
#                                waits on before flushing buffered client data.
#
# The delay now sits on the ClientNIC↔ServerNIC leg, where the ServerNIC's hold
# overlaps WAN transit instead of adding to it:
#     Baseline: SYN →RTT/2→ srv →RTT/2→ client (connect = RTT), then data
#               →RTT/2→ srv, response →RTT/2→ client   ⇒ FCT ≈ 2·RTT
#     0-RTT:    spoofed SYN-ACK returns immediately (connect ≈ 0); data is in
#               flight while ServerNIC learns the real ISN, so it flushes on
#               arrival                                 ⇒ FCT ≈ RTT
#     saving  = NETEM_RTT_MS on BOTH send_unlock and FCT
#
# This function therefore only *removes* endpoint qdiscs and asserts they are
# gone. See wan_tune_middle_leg() and wan_delay_us() for where the delay lives.
endpoint_tune() {
    local client_iid="$1" server_iid="$2"

    # ─── TCP options + kernel limits ──────────────────────────────────────────
    # Timestamps/window-scaling/SACK off: the data plane does not rewrite TCP
    # options, so leaving them on would let the endpoints negotiate features the
    # translator cannot honour.
    log "Endpoint tuning: TCP options off, kernel limits raised (Client + Server)..."
    remote_bg "$client_iid" \
        "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; \
         sysctl -w net.ipv4.ip_local_port_range='1024 65535'; \
         sysctl -w net.ipv4.tcp_tw_reuse=1; \
         sysctl -w net.ipv4.tcp_max_tw_buckets=200000; \
         sysctl -w net.core.netdev_max_backlog=250000; \
         sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; \
         sysctl -w fs.file-max=1048576"
    remote_bg "$server_iid" \
        "sysctl -w net.ipv4.tcp_timestamps=0 net.ipv4.tcp_window_scaling=0 net.ipv4.tcp_sack=0; \
         sysctl -w net.core.somaxconn=131072 net.ipv4.tcp_max_syn_backlog=131072; \
         sysctl -w net.ipv4.tcp_max_tw_buckets=200000; \
         sysctl -w net.core.netdev_max_backlog=250000; \
         sysctl -w net.netfilter.nf_conntrack_max=200000 2>/dev/null || true; \
         sysctl -w fs.file-max=1048576"
    sleep 2

    # ─── Frame ceiling (capacity-model.md §5) ─────────────────────────────────
    # Both DPDK forwarders copy through a fixed 2048-byte buffer and measure
    # length via rte_pktmbuf_data_len() (first segment only). The AWS VPC default
    # MTU (9001) lets the server send ~9015-byte frames that arrive as chained
    # mbufs and are silently truncated. 1500 matches SPOOFED_MSS=1460 and keeps
    # every frame under the 2048-14=2034-byte ceiling. Applied to the baseline
    # too — not because the baseline needs it, but because MTU changes segment
    # count and therefore flow completion time, so it must not differ.
    log "Endpoint tuning: pinning MTU 1500 on Client and Server eth0..."
    remote_bg "$client_iid" "ip link set eth0 mtu 1500"
    remote_bg "$server_iid" "ip link set eth0 mtu 1500"
    sleep 1

    # ─── Offloads off ─────────────────────────────────────────────────────────
    # GRO/LRO coalesce segments before tcpdump sees them, which corrupts the
    # per-segment timing the analyzer derives its metrics from.
    log "Endpoint tuning: disabling GRO/LRO/TSO/GSO on Client and Server NICs..."
    remote_bg "$client_iid" "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"
    remote_bg "$server_iid" "ethtool -K eth0 gro off lro off tso off gso off 2>/dev/null || true"

    # ─── Emulated WAN: NOT here. Both endpoints must be clean. ────────────────
    # The emulated WAN moved to the ClientNIC<->ServerNIC leg (roadmap.md F2,
    # measurement-methodology-review.md §E). An endpoint qdisc cannot model it:
    #   - Server egress  -> `send_unlock` correct, FCT gain impossible. The real
    #     SYN-ACK is the packet ServerNIC needs before it can flush buffered
    #     client data, so delaying it delays the flush by exactly the modelled
    #     RTT. This was the 2026-08-04 configuration and is why FCT read -0.09 ms.
    #   - Client egress  -> the SYN pays before ClientNIC can spoof; no gain at all.
    #   - 50/50 split    -> halves the spoof, flush still late.
    #   - Server ingress -> the flush re-pays the same delay.
    # See wan_tune_middle_leg() below for where it now lives.
    log "Endpoint tuning: clearing any endpoint qdisc (emulated WAN lives on the middle leg)..."
    remote_bg "$client_iid" "tc qdisc del dev eth0 root 2>/dev/null || true"
    remote_bg "$server_iid" "tc qdisc del dev eth0 root 2>/dev/null || true"
    sleep 3

    # Verify, rather than assume — inverted from the old check: a leftover
    # endpoint qdisc silently reintroduces exactly the confound F2 removes, and
    # would make the FCT number unreadable without saying so.
    local client_qdisc server_qdisc
    client_qdisc=$(remote_stdout "$client_iid" "tc qdisc show dev eth0 2>&1" 30)
    server_qdisc=$(remote_stdout "$server_iid" "tc qdisc show dev eth0 2>&1" 30)
    if echo "$client_qdisc" | grep -q "netem"; then
        fail "Endpoint tuning: Client egress still has netem — the emulated WAN belongs on the middle leg (F2): $client_qdisc"
    else
        pass "Endpoint tuning: Client egress clean (no netem)"
    fi
    if echo "$server_qdisc" | grep -q "netem"; then
        fail "Endpoint tuning: Server egress still has netem — this makes an FCT gain structurally impossible (F2): $server_qdisc"
    else
        pass "Endpoint tuning: Server egress clean (no netem)"
    fi
}

# wan_tune_middle_leg <clientnic-iid> <clientnic-if> <servernic-iid> <servernic-if>
#
# Emulated WAN for a KERNEL-ROUTED middle leg (the baseline stack). Puts half of
# NETEM_RTT_MS on each NIC VM's middle-leg egress, so a round trip across the
# leg costs the full modelled RTT in both directions.
#
# The DPDK stack cannot use this: its middle-leg ports are vfio-pci owned and
# invisible to `tc`. It gets the identical delay from --wan-delay-us on both
# forwarder binaries (src/*/wan_delay.c). BOTH STACKS MUST MODEL THE SAME TOTAL
# RTT or the comparison is void.
wan_tune_middle_leg() {
    local cn_iid="$1" cn_if="$2" sn_iid="$3" sn_if="$4"
    local half=$(( NETEM_RTT_MS / 2 ))

    # `tc` is NOT in the Amazon Linux 2 base AMI — it lives in the iproute-tc
    # package, which the CDK stacks do not install (roadmap.md F15). Every run
    # before 2026-08-04 had its netem command fail with "tc: command not found",
    # swallowed by `2>/dev/null || true`, and silently measured the ~1.5 ms
    # intra-VPC RTT. Install here so the fix reaches already-running stacks.
    log "WAN tuning: ensuring iproute-tc is installed on both NIC VMs..."
    remote_run "$cn_iid" \
        "command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2" 180 > /dev/null
    remote_run "$sn_iid" \
        "command -v tc >/dev/null || yum install -y iproute-tc 2>&1 | tail -2" 180 > /dev/null

    # netem's default queue limit is 1000 packets; at this RTT a window's worth
    # of many parallel flows exceeds that and tail-drops, manufacturing loss.
    # Raise the limit so netem emulates pure delay, not delay+loss — matching
    # the DPDK side's WAN_DELAY_RING headroom.
    log "WAN tuning: netem ${half}ms on each middle-leg egress (ClientNIC $cn_if, ServerNIC $sn_if) = ${NETEM_RTT_MS}ms RTT..."
    remote_bg "$cn_iid" \
        "tc qdisc del dev $cn_if root 2>/dev/null || true; \
         tc qdisc add dev $cn_if root netem delay ${half}ms limit 1000000 2>/dev/null || true"
    remote_bg "$sn_iid" \
        "tc qdisc del dev $sn_if root 2>/dev/null || true; \
         tc qdisc add dev $sn_if root netem delay ${half}ms limit 1000000 2>/dev/null || true"
    sleep 3

    local cn_qdisc sn_qdisc
    cn_qdisc=$(remote_stdout "$cn_iid" "tc qdisc show dev $cn_if 2>&1" 30)
    sn_qdisc=$(remote_stdout "$sn_iid" "tc qdisc show dev $sn_if 2>&1" 30)
    if echo "$cn_qdisc" | grep -q "delay ${half}ms"; then
        pass "WAN tuning: ClientNIC $cn_if netem = ${half}ms (half the modelled RTT)"
    else
        fail "WAN tuning: ClientNIC $cn_if netem NOT applied — got: $cn_qdisc"
    fi
    if echo "$sn_qdisc" | grep -q "delay ${half}ms"; then
        pass "WAN tuning: ServerNIC $sn_if netem = ${half}ms (half the modelled RTT)"
    else
        fail "WAN tuning: ServerNIC $sn_if netem NOT applied — got: $sn_qdisc"
    fi
}

# wan_delay_us — half the modelled RTT in microseconds, for the DPDK
# forwarders' --wan-delay-us. Each forwarder delays its own middle-leg egress,
# so the round trip across the leg costs NETEM_RTT_MS in total, identical to
# what wan_tune_middle_leg() applies on the baseline stack.
wan_delay_us() {
    echo $(( NETEM_RTT_MS * 1000 / 2 ))
}

# endpoint_capture_start <client-iid> <server-iid> <bpf-port-filter>
# Starts nanosecond-precision tcpdump on both endpoints' eth0.
endpoint_capture_start() {
    local client_iid="$1" server_iid="$2" bpf_ports="$3"

    log "Endpoint capture: starting tcpdump on Client host and Server host..."
    remote_run "$client_iid" \
        "pkill tcpdump 2>/dev/null || true; rm -f /tmp/client_side.pcap" 30 > /dev/null
    remote_run "$server_iid" \
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

    _hiprec_start "$client_iid" "eth0" "tcp $bpf_ports" "/tmp/client_side.pcap"
    _hiprec_start "$server_iid" "eth0" "tcp $bpf_ports" "/tmp/server_side.pcap"
    sleep 2
}

# endpoint_capture_stop <client-iid> <server-iid>
endpoint_capture_stop() {
    local client_iid="$1" server_iid="$2"
    remote_run "$client_iid" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
    remote_run "$server_iid" "pkill tcpdump 2>/dev/null || true; sleep 1" 30 > /dev/null
}

# endpoint_analyze <client-iid> <server-iid> <repo-path>
#
# Runs analyze_metrics.py on each endpoint host, against the capture that host
# owns, and merges the two key=value outputs. Sets ENDPOINT_METRICS.
#
# Option A — analyze in place, ship only the summary. SSM caps
# StandardOutputContent at 24 KB and inline command params at 8 KB, so the
# 20-40 MB endpoint pcaps cannot be shipped between hosts. That same 24 KB cap
# applies to the ANALYZER OUTPUT, which is why --summary is mandatory and not an
# optimization: per-flow lines cost ~170 bytes each, so a 68,779-flow run emitted
# ~11 MB and SSM silently returned only the first 144 flows — mid-line, with no
# error — making every reported percentile a statistic over an arbitrary 0.2%
# prefix. --summary aggregates on the capture host and crosses the wire at a
# constant ~250 bytes; --detail-out keeps the full per-flow lines on the endpoint.
endpoint_analyze() {
    local client_iid="$1" server_iid="$2" repo="$3"
    local timeout="${ANALYSIS_TIMEOUT:-600}"

    local client_pcap_size server_pcap_size
    client_pcap_size=$(remote_stdout "$client_iid" \
        "ls -lh /tmp/client_side.pcap 2>&1 || echo 'pcap file not found'" 30)
    server_pcap_size=$(remote_stdout "$server_iid" \
        "ls -lh /tmp/server_side.pcap 2>&1 || echo 'pcap file not found'" 30)
    echo "  client_side.pcap: $client_pcap_size"
    echo "  server_side.pcap: $server_pcap_size"

    log "Endpoint analysis: running analyzer on the Client host capture..."
    local c_result c_status c_stdout c_stderr
    c_result=$(remote_run "$client_iid" \
        "python3 $repo/experiments/utils/analyze_metrics.py \
            --client-pcap /tmp/client_side.pcap \
            --summary --detail-out /tmp/client_metrics_per_flow.txt" \
        "$timeout")
    c_status=$(echo "$c_result" | json_idx 0)
    c_stdout=$(echo "$c_result" | json_idx 1)
    c_stderr=$(echo "$c_result" | json_idx 2)

    log "Endpoint analysis: running analyzer on the Server host capture..."
    local s_result s_status s_stdout s_stderr
    s_result=$(remote_run "$server_iid" \
        "python3 $repo/experiments/utils/analyze_metrics.py \
            --server-pcap /tmp/server_side.pcap \
            --summary --detail-out /tmp/server_metrics_per_flow.txt" \
        "$timeout")
    s_status=$(echo "$s_result" | json_idx 0)
    s_stdout=$(echo "$s_result" | json_idx 1)
    s_stderr=$(echo "$s_result" | json_idx 2)

    ENDPOINT_METRICS=$(printf '%s\n%s' "$c_stdout" "$s_stdout")

    echo "--- Endpoint metric analysis ---"
    echo "client (status: $c_status):"
    echo "$c_stdout"
    [[ -n "$c_stderr" ]] && echo "  stderr: $c_stderr"
    echo "server (status: $s_status):"
    echo "$s_stdout"
    [[ -n "$s_stderr" ]] && echo "  stderr: $s_stderr"
    echo "--------------------------------"

    if [[ "$c_status" == "Success" && "$s_status" == "Success" ]] && \
       ! echo "$ENDPOINT_METRICS" | grep -q "^missing="; then
        pass "Endpoint analysis: all metrics computed"
    else
        # In --summary mode each missing= line carries count=<k> flows, so sum
        # those rather than counting lines — otherwise 31k unestablished flows
        # report as "2".
        local nmissing
        nmissing=$(printf '%s' "$ENDPOINT_METRICS" | python3 -c '
import sys, re
total = lines = 0
for line in sys.stdin:
    if not line.startswith("missing="):
        continue
    lines += 1
    m = re.search(r"\bcount=(\d+)", line)
    total += int(m.group(1)) if m else 1
print(total if lines else 0)
' 2>/dev/null || echo "?")
        fail "Endpoint analysis: $nmissing missing metric event(s) (client=$c_status server=$s_status)"
    fi
}

# endpoint_latency_summary <extra-lines>
#
# Renders the standard latency block. send_unlock leads because it is the only
# metric that isolates what the spoof actually buys: the client's
# open_connection() returns on the (spoofed) SYN-ACK and the first write follows
# immediately, so send_unlock is first-SYN-out → first-payload-out with no
# transfer time mixed in. FCT and server_gap are reported below it as secondary
# — both are throughput-bound and move with payload size, link speed and loss,
# so a change in either is not by itself evidence about the handshake.
endpoint_latency_summary() {
    local metrics="$1"
    echo "  ── Primary: time-to-first-byte the client actually experiences ──"
    echo "$metrics" | summarize_metric "send_unlock" "client" "Send unlock   "
    echo "  ── Secondary (throughput-bound; not evidence about the handshake) ──"
    echo "$metrics" | summarize_metric "fct"        "client" "Pcap FCT      "
    echo "$metrics" | summarize_metric "server_gap" "server" "Server gap    "
}
