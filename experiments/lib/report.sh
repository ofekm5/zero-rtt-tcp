#!/usr/bin/env bash
# Shared report-writing helpers used by experiments/run.sh (write_run_report
# below). Every report is built from
# the same two repeating shapes: a title/impl-info/overall-result header, and
# a "## Heading" followed by a fenced code block (optionally through
# `tail -N`). Extracted here once; each caller supplies its own middle
# section content and order, which differs per implementation.

# report_header [TITLE_TEXT] IMPL_INFO OVERALL_RESULT [DATE_FORMAT]
#   TITLE_TEXT     — report title, before " — <date>" (default: the shared
#                    "Integration Test Report" title used by dpdk/scapy;
#                    pass "" to take the default). baseline-tcp overrides it.
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
#     baseline        baseline-tcp/  baseline-report-<date-time>.md
#   Reads FAILURES, CONNECTIONS, the LOAD_*/NETEM_RTT_MS knobs, CLIENT_STDOUT,
#   the CORE_* results run_experiment exports and (ssh only) LAB_GATEWAY.
write_run_report() {
    local stack="$1" transport="$2" dir file
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reports/$stack"
    mkdir -p "$dir"
    case "$stack/$transport" in
        0rtt/ssm) file="$dir/integration-test-report-$(date +%Y-%m-%d).md"; _report_0rtt_ssm > "$file" ;;
        0rtt/ssh) file="$dir/proxmox-test-report-$(date +%Y-%m-%d).md";     _report_0rtt_ssh > "$file" ;;
        # ponytail: baseline+ssh reuses the SSM baseline body — no lab runner existed to copy
        baseline/*) file="$dir/baseline-report-$(date +%Y-%m-%d-%H%M%S).md"; _report_baseline > "$file" ;;
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
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (Server egress only) |"
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
    local overall_result
    if [[ $FAILURES -eq 0 ]]; then
        overall_result="ALL PASSED"
    else
        overall_result="$FAILURES FAILURE(S)"
    fi

    echo "# Proxmox 0-RTT Test Report — $(date +%Y-%m-%d)"
    echo ""
    echo "**Implementation**: DPDK (ISN ack-num translation shift)"
    echo "**Infra**: RUNS Proxmox lab — 4 VMs via SSH gateway (${LAB_GATEWAY})"
    echo "**ClientNIC binary**: \`src/clientnic/dpdk-forwarder/\` (transparent forwarder + V-stamp)"
    echo "**ServerNIC binary**: \`src/servernic/dpdk/\` (full translator)"
    echo "**Experiment script**: \`experiments/run.sh\`"
    echo "**Transport**: SSH jump host via \`experiments/lib/transport/ssh_lab.sh\`"
    echo "**Overall result**: $overall_result"
    echo ""
    report_section "Latency Summary (TTFB @ 3 points + FCT)" "${CORE_METRICS_SUMMARY:-}"
    report_section "Client Output" "${CLIENT_STDOUT:-}"
    report_section "ClientNIC Log (0-RTT activity)" "${CORE_CLIENTNIC_LOG:-}" 50
    report_section "ServerNIC Log" "${CORE_SERVERNIC_LOG:-}" 30
    report_section "Server Log" "${CORE_SERVER_LOG:-}" 20
    report_section "Packet Analysis" "${CORE_ENDPOINT_METRICS:-}" "" 1
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
    echo "| \`NETEM_RTT_MS\` | $NETEM_RTT_MS (Server egress only) |"
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
    echo "- Emulated RTT is applied entirely on the Server VM's egress, so the leg"
    echo "  0-RTT short-circuits carries the full \`NETEM_RTT_MS\`. See endpoint.sh."
    echo "- **Compare \`Send unlock\` against \`experiments/reports/0rtt/\`** — that is"
    echo "  the metric the 0-RTT mechanism acts on. FCT and server gap are"
    echo "  throughput-bound and move with payload size and loss."
}
