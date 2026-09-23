#!/usr/bin/env bash
# Shared "Integration Test Report" writer for experiments/dpdk and
# experiments/scapy — both produced byte-identical header/tail markdown
# (title, Client Output / ClientNIC Log / ServerNIC Log / Server Log /
# Packet Analysis sections with the same tail(1) line counts) around a
# middle section that differs per implementation. Parameterised on what
# differs; the shared shape lives here once.
#
# Usage:
#   write_integration_report REPORT_FILE IMPL_INFO OVERALL_RESULT EXTRA_BODY \
#       CLIENT_STDOUT CLIENTNIC_LOG SERVERNIC_LOG SERVER_LOG PACKET_ANALYSIS
#
#   IMPL_INFO    — one or more "**Key**: value" markdown lines (no header/blank)
#   EXTRA_BODY   — optional markdown inserted after Overall result (e.g. dpdk's
#                  Load Parameters / Latency Summary); pass "" to omit
write_integration_report() {
    local report_file="$1" impl_info="$2" overall_result="$3" extra_body="$4"
    local client_stdout="$5" clientnic_log="$6" servernic_log="$7" server_log="$8" packet_analysis="$9"

    {
        echo "# Integration Test Report — $(date +%Y-%m-%d)"
        echo ""
        printf '%s\n' "$impl_info"
        echo "**Overall result**: $overall_result"
        echo ""
        if [[ -n "$extra_body" ]]; then
            printf '%s\n' "$extra_body"
            echo ""
        fi
        echo "## Client Output"
        echo ""
        echo '```'
        echo "$client_stdout"
        echo '```'
        echo ""
        echo "## ClientNIC Log (0-RTT activity)"
        echo ""
        echo '```'
        echo "$clientnic_log" | tail -50
        echo '```'
        echo ""
        echo "## ServerNIC Log"
        echo ""
        echo '```'
        echo "$servernic_log" | tail -30
        echo '```'
        echo ""
        echo "## Server Log"
        echo ""
        echo '```'
        echo "$server_log" | tail -20
        echo '```'
        echo ""
        echo "## Packet Analysis"
        echo ""
        echo '```'
        echo "$packet_analysis"
        echo '```'
    } > "$report_file"
}
