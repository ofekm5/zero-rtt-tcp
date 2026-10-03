#!/usr/bin/env bash
# Run on the Server VM.
# Cleans up, pulls latest code, starts the load-generator server in the foreground.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this first and wait until "Listening on ports" appears.
#
# Usage (on the Server VM via SSM or SSH):
#   cd /home/ec2-user/zero-rtt-tcp/experiments/nodes
#   ./server.sh
#
# The script blocks in the foreground. Press Ctrl+C to stop.

set -uo pipefail

REPO_PATH="${REPO_PATH:-/home/ec2-user/zero-rtt-tcp}"
SERVER_PORT=8080
# Number of contiguous ports to listen on (SERVER_PORT .. SERVER_PORT+LOAD_PORTS-1).
# The client spreads its parallel connections across these to clear the per-port
# ephemeral-port ceiling. Must match the data plane's --port-count.
LOAD_PORTS="${LOAD_PORTS:-4}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Cleanup ──────────────────────────────────────────────────────────────────
log "Killing any leftover load-generator processes..."
pkill -f 'loadgen.py' 2>/dev/null || true
sleep 1

# ─── Check python3 available ──────────────────────────────────────────────────
command -v python3 >/dev/null || { echo -e "${RED}ERROR: python3 not installed${NC}"; exit 1; }

# Raise the open-file limit so the server can accept the client's parallel
# connections (up to 100000 concurrent sockets across all listening ports).
ulimit -n 1048576 2>/dev/null || ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
log "Open-file limit (ulimit -n): $(ulimit -n)"

# ─── Pull latest code ─────────────────────────────────────────────────────────
# REPO_REF defaults to main; override to run a branch (e.g. to validate a
# harness change on real infra before merging it).
REPO_REF="${REPO_REF:-main}"
log "Syncing code to origin/${REPO_REF} (hard reset — discards VM-local drift)..."
sudo -u ec2-user git -C "$REPO_PATH" fetch origin "$REPO_REF" 2>&1 \
    && sudo -u ec2-user git -C "$REPO_PATH" reset --hard "origin/$REPO_REF" 2>&1 \
    || log "WARNING: git sync failed — using current checkout"

# ─── Pre-flight ───────────────────────────────────────────────────────────────
MY_IP=$(hostname -I | awk '{print $1}')
SERVER_PORT_HI=$(( SERVER_PORT + LOAD_PORTS - 1 ))
log "Server VM IP: $MY_IP"
log "Will listen on 0.0.0.0:${SERVER_PORT}-${SERVER_PORT_HI} ($LOAD_PORTS port(s))"
echo ""

# ─── Start the load-generator server (single asyncio process, all ports) ─────
# One event-driven process handles every port — no thread-per-connection, no
# thread-per-port either (see experiments/nodes/loadgen.py).
log "Starting load-generator server on ports ${SERVER_PORT}-${SERVER_PORT_HI} — press Ctrl+C to stop."
echo ""

# ─── QUIC arm (PROTO=quic) ────────────────────────────────────────────────────
# PROTO unset (or tcp) falls through to loadgen.py exactly as before.
if [ "${PROTO:-tcp}" = "quic" ]; then
    pkill -f 'loadgen_quic.py' 2>/dev/null || true
    # Python 3.11 + aioquic 1.3.0, separate from the system python3: see
    # ensure_quic_python.sh.
    QUIC_PY=$(bash "$REPO_PATH/experiments/nodes/ensure_quic_python.sh") || {
        log "ERROR: could not set up the QUIC interpreter"
        exit 1
    }
    # Throwaway self-signed cert: the client does not verify it. EC P-256, the
    # same key type the rate-spike calibration uses (loadgen_quic._write_cert).
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 1 \
        -subj "/CN=loadgen" -keyout /tmp/quic.key -out /tmp/quic.crt || {
        log "ERROR: openssl could not generate the QUIC cert"
        exit 1
    }
    exec "$QUIC_PY" "$REPO_PATH/experiments/nodes/loadgen_quic.py" --mode server \
        --port "$SERVER_PORT" --port-count "$LOAD_PORTS" \
        --cert /tmp/quic.crt --key /tmp/quic.key
fi

exec python3 "$REPO_PATH/experiments/nodes/loadgen.py" --mode server \
    --port "$SERVER_PORT" --port-count "$LOAD_PORTS"
