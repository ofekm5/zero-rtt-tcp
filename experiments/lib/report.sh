#!/usr/bin/env bash
# Shared report-writing helpers used by experiments/run.sh (write_run_report
# below). Every report is built from
# the same two repeating shapes: a title/impl-info/overall-result header, and
# a "## Heading" followed by a fenced code block (optionally through
# `tail -N`). Extracted here once; each caller supplies its own middle
# section content and order, which differs per implementation.

# report_header [TITLE_TEXT] IMPL_INFO OVERALL_RESULT [DATE_FORMAT]
#   TITLE_TEXT     — report title, before " — <date>" (default: the shared
#                    "Integration Test Report" title used by _report_0rtt_ssm;
#                    pass "" to take the default). _report_baseline overrides it.
#   IMPL_INFO      — one or more "**Key**: value" markdown lines
#   OVERALL_RESULT — caller-formatted result string (may include emoji)
#   DATE_FORMAT    — strftime format for the title date (default: %Y-%m-%d)
report_header() {
    local title_text="${1:-Integration Test Report}" impl_info="$2" overall_result="$3"
    local date_fmt="${4:-%Y-%m-%d}"
    echo "# $title_text — $(date +"$date_fmt")"
    echo ""
    printf '%s\n' "$impl_info"
    echo "**Overall result**: $overall_result"
    echo ""
}

# report_section HEADING CONTENT [TAIL_N] [NO_TRAILING_BLANK]
#   Prints "## HEADING", a fenced code block of CONTENT (optionally piped
#   through `tail -N`), and a trailing blank line — unless NO_TRAILING_BLANK
#   is non-empty, for the last section in a report (matches the pre-refactor
#   writers, which ended right after the closing fence with no blank line).
report_section() {
    local heading="$1" content="$2" tail_n="${3:-}" no_trailing_blank="${4:-}"
    echo "## $heading"
    echo ""
    echo '```'
    if [[ -n "$tail_n" ]]; then
        echo "$content" | tail -"$tail_n"
    else
        echo "$content"
    fi
    echo '```'
    if [[ -z "$no_trailing_blank" ]]; then
        echo ""
    fi
}

# write_run_report STACK TRANSPORT
#   Writes run.sh's report under experiments/reports/<STACK>/ (resolved from this
#   file's own location, so it is independent of the caller's cwd) and logs the
#   path. Body and filename are the ones the matching pre-run.sh runner wrote:
#     0rtt     + ssm  dpdk/     integration-test-report-<date>.md
#     0rtt     + ssh  proxmox/  proxmox-test-report-<date>.md
#     baseline        baseline-tcp/  baseline-report-<date-time>.md  (run.sh rejects baseline+ssh)
#   Reads FAILURES, CONNECTIONS, the LOAD_*/NETEM_RTT_MS knobs, CLIENT_STDOUT,
#   the CORE_* results run_experiment exports and (ssh only) LAB_GATEWAY.
write_run_report() {
    local stack="$1" transport="$2" dir file
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reports/$stack"
    mkdir -p "$dir"
    case "$stack/$transport" in
        0rtt/ssm) file="$dir/integration-test-report-$(date +%Y-%m-%d).md"; _report_0rtt_ssm > "$file" ;;
        0rtt/ssh) file="$dir/proxmox-test-report-$(date +%Y-%m-%d).md";     _report_0rtt_ssh > "$file" ;;
        baseline/*)
            if [[ "${PROTO:-tcp}" == quic ]]; then
                local arm=cold
                [[ "${QUIC_RESUME:-0}" == 1 ]] && arm=resumed
                file="$dir/baseline-quic-$arm-report-$(date +%Y-%m-%d-%H%M%S).md"; _report_quic "$arm" > "$file"
            else
                file="$dir/baseline-report-$(date +%Y-%m-%d-%H%M%S).md"; _report_baseline > "$file"
            fi ;;
    esac
    log "Report saved to $file"
}

_report_0rtt_ssm() {
    local overall_result impl_info
    if [[ $FAILURES -eq 0 ]]; then
        overall_result="ALL PASSED"
    else
        overall_result="$FAILURES FAILURE(S)"
    fi

    impl_info=$(
        echo "**Implementation**: DPDK (ISN ack-num translation shift)"
        echo "**ClientNIC binary**: \`src/clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
        echo "**ServerNIC binary**: \`src/servernic/dpdk/\` (full translator)"
        echo "**Experiment script**: \`experiments/run.sh\`"
        echo "**Node scripts**: \`experiments/nodes/\` (clientnic/servernic/client/server)"
    )

    report_header "" "$impl_info" "$overall_result"
    _report_0rtt_body
}

# Everything after the header, shared by both 0rtt transports.
_report_0rtt_body() {
    if [[ "${LOAD_RATE:-2000}" == "0" ]]; then
        echo "> **CAPACITY RUN — \`LOAD_RATE=0\`.** Connections arrived as a single"
        echo "> burst, so every flow's latency includes queueing behind the rest of"
        echo "> the batch. Valid readings: establishment success rate and data-plane"
        echo "> throughput. **Not** valid: any 0-RTT latency claim. For a latency"
        echo "> run use \`run.sh\` with the default paced arrival."
        echo ""
    fi
    echo "## Load Parameters"
    echo ""
    echo "Must match the baseline run being compared against — see"
    echo "\`experiments/reports/baseline/\`."
    echo ""
    echo "| Parameter | Value |"
    echo "|---|---|"
    echo "| Rounds | $CONNECTIONS |"
    echo "| \`LOAD_PARALLEL\` | $LOAD_PARALLEL |"
    echo "| \`LOAD_PORTS\` | $LOAD_PORTS |"
    echo "| \`LOAD_BYTES\` | $LOAD_BYTES |"
    echo "| \`LOAD_RATE\` | $LOAD_RATE conn/s |"
    echo "| \`LOAD_CONCURRENCY\` | $LOAD_CONCURRENCY |"
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (ClientNIC↔ServerNIC leg, half per direction) |"
    echo ""
    echo "## Latency Summary"
    echo ""
    echo "\`Send unlock\` is the primary result: first SYN out → first payload out,"
    echo "which is exactly what the spoofed SYN-ACK unblocks. Compare it against the"
    echo "baseline's \`Send unlock\`; the expected saving is one \`NETEM_RTT_MS\`."
    echo ""
    echo '```'
    echo "${CORE_METRICS_SUMMARY:-}"
    echo '```'
    echo ""
    report_section "Client Output" "${CLIENT_STDOUT:-}"
    report_section "ClientNIC Log (0-RTT activity)" "${CORE_CLIENTNIC_LOG:-}" 50
    report_section "ServerNIC Log" "${CORE_SERVERNIC_LOG:-}" 30
    report_section "Server Log" "${CORE_SERVER_LOG:-}" 20
    report_section "Packet Analysis" "${CORE_ENDPOINT_METRICS:-}" "" 1
}

_report_0rtt_ssh() {
    local overall_result impl_info
    if [[ $FAILURES -eq 0 ]]; then
        overall_result="ALL PASSED"
    else
        overall_result="$FAILURES FAILURE(S)"
    fi

    impl_info=$(
        echo "**Implementation**: DPDK (ISN ack-num translation shift)"
        echo "**Infra**: RUNS Proxmox lab — 4 VMs via SSH gateway (${LAB_GATEWAY:-})"
        echo "**ClientNIC binary**: \`src/clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
        echo "**ServerNIC binary**: \`src/servernic/dpdk/\` (full translator)"
        echo "**Experiment script**: \`experiments/run.sh\`"
        echo "**Transport**: SSH jump host via \`experiments/lib/transport/ssh_lab.sh\`"
    )

    report_header "Proxmox 0-RTT Test Report" "$impl_info" "$overall_result"
    _report_0rtt_body
}

_report_baseline() {
    local overall_result impl_info
    if [[ $FAILURES -eq 0 ]]; then overall_result="ALL PASSED ✅"; else overall_result="$FAILURES FAILURE(S) ❌"; fi

    impl_info=$(
        echo "**Mode**: Plain TCP (no 0-RTT middleware)"
        echo "**Infra**: \`infra/baseline\` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding"
    )

    report_header "Baseline TCP Report" "$impl_info" "$overall_result" "%Y-%m-%d-%H%M%S"
    echo "## Load Parameters"
    echo ""
    echo "These must match the 0-RTT run being compared against, or the comparison"
    echo "is confounded. Both stacks read them from \`experiments/lib/measure.sh\`"
    echo "and configure endpoints via \`experiments/lib/endpoint.sh\`."
    echo ""
    echo "| Parameter | Value |"
    echo "|---|---|"
    echo "| Rounds | $CONNECTIONS |"
    echo "| \`LOAD_PARALLEL\` | $LOAD_PARALLEL |"
    echo "| \`LOAD_PORTS\` | $LOAD_PORTS |"
    echo "| \`LOAD_BYTES\` | $LOAD_BYTES |"
    echo "| \`LOAD_RATE\` | $LOAD_RATE conn/s |"
    echo "| \`LOAD_CONCURRENCY\` | $LOAD_CONCURRENCY |"
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (ClientNIC↔ServerNIC leg, half per direction) |"
    echo ""
    report_section "Latency Summary" "${CORE_METRICS_SUMMARY:-}"
    report_section "Client Output" "${CLIENT_STDOUT:-}"
    report_section "Endpoint Packet Analysis" "${CORE_ENDPOINT_METRICS:-}"
    report_section "Server Log" "${CORE_SERVER_LOG:-}" 20
    echo "## Notes"
    echo ""
    echo "- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server"
    echo "- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1"
    echo "- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0"
    echo "- Emulated RTT sits on the ClientNIC↔ServerNIC leg (netem, half per"
    echo "  direction), the leg 0-RTT short-circuits. See endpoint.sh and"
    echo "  measurement-methodology-review.md §E."
    echo "- **Compare \`Send unlock\` against \`experiments/reports/0rtt/\`** — that is"
    echo "  the metric the 0-RTT mechanism acts on. FCT and server gap are"
    echo "  throughput-bound and move with payload size and loss."
}

# _report_quic <cold|resumed> — the QUIC arm on the baseline stack (PROTO=quic).
# No packet-analysis section: QUIC is encrypted, so no capture is taken.
_report_quic() {
    local arm="$1" overall_result impl_info
    if [[ $FAILURES -eq 0 ]]; then overall_result="ALL PASSED ✅"; else overall_result="$FAILURES FAILURE(S) ❌"; fi

    impl_info=$(
        echo "**Mode**: QUIC $arm (\`PROTO=quic QUIC_RESUME=${QUIC_RESUME:-0}\`, \`experiments/nodes/loadgen_quic.py\`, aioquic)"
        echo "**Infra**: \`infra/baseline\` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding"
    )

    report_header "QUIC $arm Report" "$impl_info" "$overall_result" "%Y-%m-%d-%H%M%S"
    echo "## Load Parameters"
    echo ""
    echo "These must match the TCP baseline, 0-RTT TCP and the other QUIC run being"
    echo "compared against, or the four-arm comparison is confounded."
    echo ""
    echo "| Parameter | Value |"
    echo "|---|---|"
    echo "| \`PROTO\` | quic |"
    echo "| \`QUIC_RESUME\` | ${QUIC_RESUME:-0} ($arm) |"
    echo "| Rounds | $CONNECTIONS |"
    echo "| \`LOAD_PARALLEL\` | $LOAD_PARALLEL |"
    echo "| \`LOAD_PORTS\` | $LOAD_PORTS |"
    echo "| \`LOAD_BYTES\` | $LOAD_BYTES |"
    echo "| \`LOAD_RATE\` | $LOAD_RATE conn/s |"
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (ClientNIC↔ServerNIC leg, half per direction) |"
    echo ""
    echo "\`LOAD_CONCURRENCY\` and \`LOAD_THINK_MS\` do not apply: \`loadgen_quic.py\` has neither knob."
    echo ""
    report_section "Latency Summary" "${CORE_METRICS_SUMMARY:-}"
    report_section "Client Output" "${CLIENT_STDOUT:-}"
    report_section "Server Log" "${CORE_SERVER_LOG:-}" 20
    echo "## Notes"
    echo ""
    echo "- **Plaintext vs encrypted.** The TCP baseline and 0-RTT TCP arms are plaintext;"
    echo "  QUIC always encrypts. \`send_unlock\` here includes the TLS 1.3 handshake work"
    echo "  the TCP arms never do."
    echo "- **One ticket, reused.** Each client process makes one priming connection and"
    echo "  every resumed flow reuses its session ticket, so all resumed flows are"
    echo "  \"returning users\"."
    echo "- **Different data plane for the 0-RTT TCP arm.** TCP baseline, QUIC cold and QUIC"
    echo "  resumed run on this kernel-routed baseline stack; 0-RTT TCP runs on the DPDK"
    echo "  stack, so NIC-side processing differences land inside that arm's number."
    echo "- **Metric.** \`send_unlock\` is app-side (connect start → first write permitted),"
    echo "  taken on the client's own clock by \`loadgen_quic.py\`. No pcap capture and no"
    echo "  \`analyze_metrics.py\` run for QUIC; \`fct\` and \`server_gap\` are not measured."
    echo "- **A2 escalation triggers** — read off the \`quic_summary\` line above; if any"
    echo "  holds, add the pcap header cross-check:"
    echo "  - cold \`send_unlock_p50_ms\` is not near \`NETEM_RTT_MS\` ($NETEM_RTT_MS);"
    echo "  - resumed \`send_unlock_p50_ms\` is not clearly below cold;"
    echo "  - \`early_data_accepted\` is below n/n on a resumed run (expected 0/n cold);"
    echo "  - resumed \`handshake_p50_ms\` equals cold (resumption silently fell back)."
    echo "- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server, UDP."
}
