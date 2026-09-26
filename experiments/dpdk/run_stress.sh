#!/usr/bin/env bash
# Capacity / stress run for the 0-RTT DPDK stack — DELIBERATELY unpaced.
#
# This is a different question from run_experiment.sh, and the separation is the
# point. run_experiment.sh asks "does the translation mechanism remove one RTT?"
# — a protocol question, answered by paced arrivals and per-connection latency.
# This script asks "where does this data plane break?" — an engineering
# question, answered by firing everything at once and counting what survives.
#
# Fusing the two (which the harness used to do) answers neither well: a burst
# makes every latency sample include queueing behind the whole batch, and a
# success rate depressed by endpoint resource exhaustion says nothing about
# whether sequence-number translation is correct.
#
# WHAT YOU MAY CONCLUDE FROM THIS RUN
#   ✓ establishment success rate at a given offered load
#   ✓ where the first failure appears (endpoint vs data plane) — cross-check the
#     forwarder/translator logs before attributing it, per insights.md
#   ✓ aggregate throughput of the data plane
#   ✗ anything about 0-RTT latency benefit — the numbers are queue-dominated
#
# Usage:
#   ./experiments/dpdk/run_stress.sh                 # 100k conns, unpaced
#   LOAD_PARALLEL=250000 ./experiments/dpdk/run_stress.sh
#
# All experiments/lib/measure.sh knobs still apply; only the arrival shape and
# the concurrency ceiling are forced here.

set -uo pipefail

# LOAD_RATE=0 selects the burst path in loadgen.py. LOAD_CONCURRENCY is lifted to
# LOAD_PARALLEL so the semaphore does not quietly convert the burst back into a
# paced run — an unintended throttle would make the capacity number meaningless.
export LOAD_RATE=0
export LOAD_PARALLEL="${LOAD_PARALLEL:-100000}"
export LOAD_CONCURRENCY="${LOAD_CONCURRENCY:-$LOAD_PARALLEL}"

# Payload stays at the latency-run default unless overridden: this run is about
# how many connections can be *established*, not how much data moves. Raise
# LOAD_BYTES explicitly if throughput is what you are after.
export LOAD_BYTES="${LOAD_BYTES:-1024}"

YELLOW='\033[1;33m'; NC='\033[0m'
echo -e "${YELLOW}"
echo "════════════════════════════════════════════════════════════════"
echo "  CAPACITY RUN — unpaced burst (LOAD_RATE=0)"
echo "  ${LOAD_PARALLEL} connections, ${LOAD_BYTES} bytes each, no arrival pacing"
echo ""
echo "  Latency figures from this run are queue-dominated and are NOT"
echo "  0-RTT results. Use run_experiment.sh for latency."
echo "════════════════════════════════════════════════════════════════"
echo -e "${NC}"

exec "$(dirname "$0")/run_experiment.sh" "$@"
