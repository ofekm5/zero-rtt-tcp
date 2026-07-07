#!/usr/bin/env bash
# ebpf-trace.sh — interactive eBPF TCP tracing for manual SSM sessions (DPDK stack)
#
# Run on the Client or Server VM during a manual experiment session.
# Traces both TCP state transitions AND retransmits. Press Ctrl+C to stop.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → [start this] → client.sh
#
# Usage (on Client or Server VM via SSM):
#   cd /home/ec2-user/zero-rtt-demo/experiments/nodes
#   ./ebpf-trace.sh [port]
#     port  TCP port to filter (default: 8080)
#
# Output: JSON lines printed to stdout as events arrive, then a summary on exit.

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"
TRACE_SCRIPT="$REPO_PATH/observability/ebpf/run_trace.sh"
PORT="${1:-8080}"
OUTPUT="/tmp/ebpf_trace_manual.jsonl"
DURATION=3600  # 1 hour max; Ctrl+C stops early

YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

log "Starting eBPF TCP trace (port=$PORT) — press Ctrl+C to stop and print summary"
log "Output file: $OUTPUT"
echo ""

# Clean up previous run
rm -f "$OUTPUT"

# run_trace.sh handles install + both state + retransmit scripts
# It blocks until DURATION seconds or Ctrl+C
bash "$TRACE_SCRIPT" \
    --duration "$DURATION" \
    --port "$PORT" \
    --output "$OUTPUT" \
    --retransmits &

TRACE_PID=$!

# Forward Ctrl+C to the trace runner
trap 'kill "$TRACE_PID" 2>/dev/null; wait "$TRACE_PID" 2>/dev/null; true' INT TERM

wait "$TRACE_PID" 2>/dev/null || true

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  eBPF Trace Summary${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"

if [[ ! -f "$OUTPUT" || ! -s "$OUTPUT" ]]; then
    echo "  No events captured."
else
    TOTAL=$(wc -l < "$OUTPUT")
    echo "  Total events: $TOTAL"
    echo ""
    echo "  TCP State Transitions:"
    # Extract and display state transitions in order
    grep '"old_state"' "$OUTPUT" | \
        python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
        ts_ms = e.get('ts_ns', 0) // 1_000_000
        print(f\"    [{ts_ms} ms]  {e.get('src','')}:{e.get('sport','')} → {e.get('dst','')}:{e.get('dport','')}  {e.get('old_state','')} → {e.get('new_state','')}\"  )
    except Exception:
        pass
" 2>/dev/null || grep '"old_state"' "$OUTPUT" | head -30

    RETRANS=$(grep -c '"seq"' "$OUTPUT" 2>/dev/null || echo 0)
    if [[ "$RETRANS" -gt 0 ]]; then
        echo ""
        echo "  Retransmit events: $RETRANS"
    fi
fi

echo -e "${GREEN}═══════════════════════════════════════${NC}"
