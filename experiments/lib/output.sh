#!/usr/bin/env bash
# Shared logging/result helpers for experiments/*/run_experiment.sh runners.
# Identical across all four runners before this hoist — source and go.
# The sourcing script must set FAILURES=0 before the first fail() call.

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
