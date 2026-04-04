#!/usr/bin/env bash
# run_trace.sh — run bpftrace TCP tracing scripts on this host
#
# Deployable via SSM:
#   bash /home/ec2-user/zero-rtt-demo/observability/ebpf/run_trace.sh \
#       --duration 30 --port 8080 --output /tmp/tcp_trace.jsonl
#
# Usage:
#   run_trace.sh --duration <sec> --port <port> --output <path> [--retransmits]
#
# Flags:
#   --duration <sec>     How long to trace (required)
#   --port <port>        TCP port to filter (default: 8080)
#   --output <path>      File to write JSON lines to (required)
#   --retransmits        Also run tcp_retransmit_trace.bt alongside state trace
#
# Output:
#   JSON lines written to <output>. State transitions and (optionally) retransmits
#   are interleaved in arrival order with monotonic ns timestamps.
#
# Exit code: 0 on success, 1 on error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DURATION=""
PORT=8080
OUTPUT=""
RETRANSMITS=false

# ─── Arg parsing ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)  DURATION="$2"; shift 2 ;;
        --port)      PORT="$2";     shift 2 ;;
        --output)    OUTPUT="$2";   shift 2 ;;
        --retransmits) RETRANSMITS=true; shift ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$DURATION" || -z "$OUTPUT" ]]; then
    echo "Usage: $0 --duration <sec> --port <port> --output <path> [--retransmits]" >&2
    exit 1
fi

# ─── Install bpftrace if missing ──────────────────────────────────────────────
if ! command -v bpftrace &>/dev/null; then
    echo "[run_trace] bpftrace not found — installing..." >&2
    amazon-linux-extras install -y BCC 2>&1 || true
    yum install -y bpftrace 2>&1
    if ! command -v bpftrace &>/dev/null; then
        echo "[run_trace] ERROR: bpftrace install failed" >&2
        exit 1
    fi
    echo "[run_trace] bpftrace installed: $(bpftrace --version)" >&2
fi

# ─── Process group cleanup on exit ────────────────────────────────────────────
PIDS=()

cleanup() {
    for pid in "${PIDS[@]:-}"; do
        kill -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done
    # Give bpftrace a moment to flush its END block
    sleep 1
}
trap cleanup EXIT INT TERM

# ─── Start state trace ────────────────────────────────────────────────────────
echo "[run_trace] Starting TCP state trace: port=$PORT duration=${DURATION}s output=$OUTPUT" >&2

# Run bpftrace under timeout, in its own process group (setsid), redirect to output file
setsid timeout "$DURATION" bpftrace "$SCRIPT_DIR/tcp_state_trace.bt" "$PORT" >> "$OUTPUT" 2>/dev/null &
STATE_PID=$!
PIDS+=("$STATE_PID")

# ─── Start retransmit trace (optional) ───────────────────────────────────────
if [[ "$RETRANSMITS" == "true" ]]; then
    echo "[run_trace] Also starting retransmit trace" >&2
    setsid timeout "$DURATION" bpftrace "$SCRIPT_DIR/tcp_retransmit_trace.bt" "$PORT" >> "$OUTPUT" 2>/dev/null &
    RETRANS_PID=$!
    PIDS+=("$RETRANS_PID")
fi

# ─── Wait for duration ────────────────────────────────────────────────────────
# Wait for all background bpftrace processes to finish (they exit when timeout fires)
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

echo "[run_trace] Trace complete. Output: $OUTPUT" >&2
LINE_COUNT=$(wc -l < "$OUTPUT" 2>/dev/null || echo 0)
echo "[run_trace] Captured $LINE_COUNT event(s)" >&2
