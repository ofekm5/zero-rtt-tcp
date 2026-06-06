#!/bin/bash
# iperf (v2) client for 0-RTT stress testing
# Runs multi-flow, parallel, burst, and stress scenarios.

SERVER=${1:-10.0.2.4}
PORT=${2:-5001}
RESULTS_DIR="/tmp/iperf_results"

mkdir -p "$RESULTS_DIR"

die() { echo "ERROR: $1" >&2; exit 1; }

run_test() {
    local name="$1"; shift
    local out="$RESULTS_DIR/${name}.txt"
    echo "--- $name ---"
    iperf -c "$SERVER" -p "$PORT" -f m "$@" | tee "$out"
    echo ""
}

command -v iperf >/dev/null || die "iperf not installed"

echo "=== iperf 0-RTT Stress Test Suite ==="
echo "Target: $SERVER:$PORT"
echo "Results: $RESULTS_DIR"
echo ""

# ── 1. Baseline: single flow, 10 s ───────────────────────────────────────────
run_test "01_baseline_single_flow" \
    -t 10

# ── 2. Sequential: 5 back-to-back connections, 5 s each ──────────────────────
echo "--- 02_sequential_5x ---"
for i in $(seq 1 5); do
    echo "  Flow $i/5"
    iperf -c "$SERVER" -p "$PORT" -f m -t 5 \
        > "$RESULTS_DIR/02_sequential_5x_run${i}.txt" 2>&1
done
echo ""

# ── 3. Parallel streams ───────────────────────────────────────────────────────
run_test "03_parallel_100000_streams" \
    -t 10 -P 100000

run_test "04_parallel_100000_streams_v2" \
    -t 10 -P 100000

# ── 4. Bulk transfers ─────────────────────────────────────────────────────────
run_test "05_bulk_100MB" \
    -n 100M

run_test "06_bulk_1GB" \
    -n 1G

# ── 5. Burst: 100 short-lived connections, 64 KB each ────────────────────────
# Each invocation opens a fresh TCP connection — hammers the SYN/flow-table path.
echo "--- 07_burst_100_short_connections ---"
for i in $(seq 1 100); do
    iperf -c "$SERVER" -p "$PORT" -f m -n 64K \
        > "$RESULTS_DIR/07_burst_conn${i}.txt" 2>&1
done
echo "  100 short connections done"
echo ""

# ── 6. Simultaneous bidirectional (-d) ───────────────────────────────────────
run_test "08_bidir_simultaneous" \
    -t 10 -d

# ── 7. Dual / sequential bidirectional (-r) ──────────────────────────────────
run_test "09_bidir_sequential" \
    -t 10 -r

# ── 8. UDP flood ──────────────────────────────────────────────────────────────
run_test "10_udp_flood_1Gbps" \
    -u -b 1G -t 10

run_test "11_udp_flood_100Mbps" \
    -u -b 100M -t 10

# ── 9. Stress: 100000 parallel streams for 60 s ──────────────────────────────
run_test "12_stress_100000p_60s" \
    -t 60 -P 100000

# ── 10. Large window size (tests buffering under 0-RTT translation) ───────────
run_test "13_large_window_256K" \
    -t 10 -w 256K

run_test "14_large_window_1M" \
    -t 10 -w 1M

# ── Summary ───────────────────────────────────────────────────────────────────
echo "=== All tests complete ==="
echo "Text results in: $RESULTS_DIR"
echo ""
echo "Quick throughput summary (sender line):"
for f in "$RESULTS_DIR"/*.txt; do
    label=$(basename "$f" .txt)
    # iperf2 summary line ends with "X Mbits/sec" (last non-blank line with "Mbits/sec")
    mbps=$(grep -oP '[\d.]+ Mbits/sec' "$f" | tail -1)
    printf "  %-48s %s\n" "$label" "${mbps:-n/a}"
done
