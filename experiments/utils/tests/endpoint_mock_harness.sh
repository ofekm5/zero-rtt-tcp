#!/usr/bin/env bash
# Mock harness for testing experiments/utils/endpoint.sh without live VMs.
#
# Substitutes the transport (remote_run/remote_bg/remote_stdout) and logging
# shims endpoint.sh expects, then sources it and invokes one of its functions.
# Every remote_* call is echoed to STDERR as:
#     TRACE|<node-id>|<command>
# so the caller can assert on what would have been sent to each node.
#
# stderr, not stdout, because endpoint.sh captures remote_stdout in command
# substitution (`x=$(remote_stdout ...)`) — a trace written to stdout there would
# be swallowed into the variable and never seen. Tracing to a stream rather than
# a scratch file keeps the harness free of any temp-dir dependency.
#
# Commands are flattened to one line: several of the real commands are multi-line
# strings, and one trace line per call is what makes the output parseable.
#
# NETEM_RTT_MS is taken as an ARGUMENT, not inherited from the environment: some
# bash builds sanitize the inherited environment, so an env-var-configured
# harness silently tests the default instead of the value under test.
#
# Usage:
#   endpoint_mock_harness.sh <netem-rtt-ms> <path-to-endpoint.sh> <function> [args...]

set -uo pipefail

export NETEM_RTT_MS="$1"; shift
ENDPOINT_SH="$1"; shift

log()  { echo "[log] $*"; }
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; }
warn() { echo "[WARN] $*"; }

_trace() { printf 'TRACE|%s|%s\n' "$1" "$(printf '%s' "$2" | tr '\n' ' ')" >&2; }

remote_bg()  { _trace "$1" "$2"; }
remote_run() { _trace "$1" "$2"; echo '["Success","",""]'; }

# `tc qdisc show` is the only stdout endpoint.sh branches on. Answer per node so
# the module sees what a correctly-tuned chain reports after the F2 change:
# BOTH endpoints clean, and half the modelled RTT on each middle-leg NIC.
remote_stdout() {
    _trace "$1" "$2"
    case "$2" in
        *"tc qdisc show"*)
            case "$1" in
                CLIENTNIC|SERVERNIC)
                    echo "qdisc netem 8001: root refcnt 2 limit 1000000 delay $(( NETEM_RTT_MS / 2 ))ms"
                    ;;
                *)
                    echo "qdisc mq 0: root"
                    ;;
            esac
            ;;
        *) echo "" ;;
    esac
}

json_idx() { :; }

# Stand-in for measure.sh's summarize_metric: echoes which metric/node it was
# asked for so ordering assertions have something stable to match on.
summarize_metric() {
    local metric="$1" node="$2" label="$3"
    cat > /dev/null
    echo "  ${label}: metric=${metric} node=${node}"
}

# shellcheck source=/dev/null
source "$ENDPOINT_SH"

"$@"
