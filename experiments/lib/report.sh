#!/usr/bin/env bash
# Shared report-writing helpers used by experiments/dpdk, experiments/scapy
# and experiments/baseline-tcp run_experiment.sh. Every report is built from
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
