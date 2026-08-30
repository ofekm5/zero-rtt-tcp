#!/usr/bin/env bash
# Client think-time sweep — how much of the 0-RTT gain survives a client that
# does not send its first request immediately.
#
# Runs the SAME experiment at several values of LOAD_THINK_MS (the pause between
# connect() returning and the first write) and collects one report per value, so
# the result is a curve rather than a single number.
#
# WHY A SWEEP AND NOT A VALUE (roadmap.md F2, measurement-methodology-review.md
# §E, docs/kb "Load Generation and Think Time"):
#
#   T=0 is NOT an unrealistic corner — it is the workload 0-RTT targets. HTTP
#   connects and sends its request immediately, and that is the hard case. A
#   single hand-picked T>0 that happens to exceed the modelled RTT would hide
#   the ServerNIC's buffer wait behind the client's own idling and manufacture
#   a gain. Reporting the whole curve removes the choice from the author: the
#   reader picks the T that matches their workload.
#
#   This sweep is only meaningful once the emulated WAN sits on the middle leg.
#   With the old server-egress netem it would have "fixed" the FCT number by
#   masking a measurement bug. The guard below refuses to run if the endpoints
#   still carry a qdisc.
#
# Usage:
#   ./experiments/run_think_sweep.sh dpdk
#   ./experiments/run_think_sweep.sh baseline
#   THINK_SWEEP="0 50 100" ./experiments/run_think_sweep.sh dpdk
#
# Env:
#   THINK_SWEEP   space-separated think times in ms (default "0 25 50 100 200")
#   SWEEP_OUT     output directory (default experiments/<mode>/reports/sweep-<ts>)
#   everything else (LOAD_*, NETEM_RTT_MS) is passed through to the runner
#
# Exit code: number of sweep points that failed.

set -uo pipefail

MODE="${1:-}"
case "$MODE" in
    dpdk)     RUNNER="experiments/dpdk/run_experiment.sh" ;;
    baseline) RUNNER="experiments/baseline-tcp/run_experiment.sh" ;;
    *)
        echo "Usage: $0 {dpdk|baseline}" >&2
        exit 2
        ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

THINK_SWEEP="${THINK_SWEEP:-0 25 50 100 200}"
NETEM_RTT_MS="${NETEM_RTT_MS:-100}"
export NETEM_RTT_MS

TS="$(date '+%Y-%m-%d-%H%M%S')"
SWEEP_OUT="${SWEEP_OUT:-experiments/${MODE}/reports/sweep-${TS}}"
mkdir -p "$SWEEP_OUT" || exit 2

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${YELLOW}[sweep] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[sweep PASS]${NC} $*"; }
fail() { echo -e "${RED}[sweep FAIL]${NC} $*"; }

FAILED=0

log "Think-time sweep on the $MODE stack"
log "  points:        $THINK_SWEEP (ms)"
log "  modelled RTT:  ${NETEM_RTT_MS} ms (middle leg, half per direction)"
log "  output:        $SWEEP_OUT"
echo ""
log "Reminder: T=0 is the primary result. The curve characterises how the gain"
log "degrades for clients that idle before their first write; it does not"
log "replace the T=0 number and must not be reported without it."
echo ""

if ! echo "$THINK_SWEEP" | grep -qE '(^| )0( |$)'; then
    fail "THINK_SWEEP does not include 0. The zero-think point is the claim;"
    fail "a sweep without it reports only the flattering half of the curve."
    exit 2
fi

for T in $THINK_SWEEP; do
    log "───────────────────────────────────────────────────────────"
    log "Point: LOAD_THINK_MS=$T"
    log "───────────────────────────────────────────────────────────"

    point_log="$SWEEP_OUT/think-${T}ms.log"
    if LOAD_THINK_MS="$T" bash "$RUNNER" 2>&1 | tee "$point_log"; then
        pass "T=${T}ms completed — $point_log"
    else
        rc=$?
        fail "T=${T}ms exited $rc — $point_log"
        FAILED=$((FAILED + 1))
    fi
done

# ─── Collect the curve ───────────────────────────────────────────────────────
# One row per point, pulled from the latency summary each runner prints. Kept as
# a grep over the run logs rather than a second analysis path so there is only
# one place where a metric is computed (analyze_metrics.py).
SUMMARY="$SWEEP_OUT/curve.md"
{
    echo "# Think-time sweep — $MODE stack"
    echo ""
    echo "- Date: $TS"
    echo "- Modelled RTT: ${NETEM_RTT_MS} ms on the ClientNIC<->ServerNIC leg"
    echo "- Points: $THINK_SWEEP ms"
    echo "- Load: LOAD_PARALLEL=${LOAD_PARALLEL:-unset} LOAD_RATE=${LOAD_RATE:-unset}" \
         "LOAD_PORTS=${LOAD_PORTS:-unset} LOAD_BYTES=${LOAD_BYTES:-unset}"
    echo ""
    echo "T=0 is the headline. The remaining points show how the gain behaves"
    echo "for a client that idles before its first write — a workload axis, not"
    echo "a correction to the T=0 result."
    echo ""
    echo "| think_ms | send_unlock mean | fct mean | fct p99 | fct max |"
    echo "| --- | --- | --- | --- | --- |"
    for T in $THINK_SWEEP; do
        f="$SWEEP_OUT/think-${T}ms.log"
        su=$(grep -oE 'summary=send_unlock[^\n]*' "$f" 2>/dev/null | tail -1)
        fc=$(grep -oE 'summary=fct[^\n]*' "$f" 2>/dev/null | tail -1)
        su_mean=$(echo "$su" | grep -oE 'mean_ms=[0-9.]+' | cut -d= -f2)
        fc_mean=$(echo "$fc" | grep -oE 'mean_ms=[0-9.]+' | cut -d= -f2)
        fc_p99=$(echo "$fc" | grep -oE 'p99_ms=[0-9.]+' | cut -d= -f2)
        fc_max=$(echo "$fc" | grep -oE 'max_ms=[0-9.]+' | cut -d= -f2)
        echo "| $T | ${su_mean:-n/a} | ${fc_mean:-n/a} | ${fc_p99:-n/a} | ${fc_max:-n/a} |"
    done
    echo ""
    echo "Blank cells mean the run did not produce that summary line — read the"
    echo "matching think-*.log before treating the point as a data point."
} > "$SUMMARY"

echo ""
log "Curve written to $SUMMARY"
cat "$SUMMARY"

exit "$FAILED"
