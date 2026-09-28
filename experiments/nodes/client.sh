#!/usr/bin/env bash
# Run on the Client VM — interactive 0-RTT load-generator client.
# Press Enter to run a new flow; each invocation opens a fresh batch of TCP connections.
#
# Startup order: server.sh → servernic.sh → clientnic.sh → client.sh
# Run this last, after clientnic.sh is ready.
#
# Usage (on the Client VM via SSH):
#   ./client.sh <server-private-ip>
#   ./client.sh               # auto-discovers server IP via EC2 API
#
# IMPORTANT: Use the Server's PRIVATE IP (e.g. 10.1.2.x), NOT the public IP.
#   The Client VM connects over the internal VPC network — the public IP is
#   not reachable from inside the VPC and will cause every connection to time out.
#
# server-ip is optional; auto-discovered from EC2 API if omitted (requires IAM permissions).

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-tcp"
SERVER_PORT=8080
REGION="eu-central-1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}"; }

# ─── Pre-flight ────────────────────────────────────────────────────────────────
command -v python3 >/dev/null || { echo -e "${RED}ERROR: python3 not installed${NC}"; exit 1; }

# Total parallel connections per flow, spread across LOAD_PORTS contiguous
# server ports so one source IP can clear the per-port ephemeral ceiling.
# experiments/nodes/loadgen.py opens every connection as an asyncio coroutine
# on one thread (epoll-driven) rather than one OS thread per connection.
#
# Defaults mirror experiments/lib/measure.sh — keep the two in sync, since a
# manual run that differs from the orchestrated one is not comparable to it.
# LOAD_RATE paces arrivals so each connection's latency reflects the path
# rather than queueing behind the rest of the batch; LOAD_BYTES is one segment
# so flow completion time is dominated by the handshake 0-RTT shortens.
# Override: LOAD_PARALLEL=N LOAD_PORTS=M LOAD_RATE=R ./client.sh
LOAD_PARALLEL="${LOAD_PARALLEL:-100000}"
LOAD_PORTS="${LOAD_PORTS:-4}"
LOAD_BYTES="${LOAD_BYTES:-1024}"
LOAD_RATE="${LOAD_RATE:-2000}"
LOAD_CONCURRENCY="${LOAD_CONCURRENCY:-2000}"
# Think time between connect() and the first write. 0 = send immediately.
LOAD_THINK_MS="${LOAD_THINK_MS:-0}"
[ "$LOAD_PORTS" -lt 1 ] && LOAD_PORTS=1
PORT_HI=$(( SERVER_PORT + LOAD_PORTS - 1 ))
ulimit -n 1048576 2>/dev/null || true

# ─── Discover server IP ───────────────────────────────────────────────────────
SERVER_IP="${1:-}"
if [ -z "$SERVER_IP" ]; then
    log "Discovering Server VM IP via EC2 API..."
    SERVER_IP=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=smartnics-server" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text --region "$REGION" 2>/dev/null | tr -d '[:space:]')
fi
if [ -z "$SERVER_IP" ] || [ "$SERVER_IP" = "None" ]; then
    echo -e "${RED}ERROR: Could not determine server IP.${NC}"
    echo "Usage: $0 <server-ip>"
    exit 1
fi

# ─── Pull latest code ─────────────────────────────────────────────────────────
# REPO_REF defaults to main; override to run a branch (e.g. to validate a
# harness change on real infra before merging it).
REPO_REF="${REPO_REF:-main}"
log "Syncing code to origin/${REPO_REF} (hard reset — discards VM-local drift)..."
sudo -u ec2-user git -C "$REPO_PATH" fetch origin "$REPO_REF" 2>&1 \
    && sudo -u ec2-user git -C "$REPO_PATH" reset --hard "origin/$REPO_REF" 2>&1 \
    || log "WARNING: git sync failed — using current checkout"

# ─── Interactive loop ─────────────────────────────────────────────────────────
CONN=0

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  0-RTT Interactive Load Generator                 ║${NC}"
echo -e "${CYAN}║  Server: ${SERVER_IP}:${SERVER_PORT}                        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Each flow opens $LOAD_PARALLEL connections across ports ${SERVER_PORT}-${PORT_HI}"
echo "($LOAD_PORTS port(s)) at ${LOAD_RATE} conn/s, $LOAD_BYTES bytes/conn,"
echo "${LOAD_THINK_MS}ms think time, max $LOAD_CONCURRENCY in flight."
echo "Press Enter for a new flow, Ctrl+C to quit."
if [ "$LOAD_RATE" = "0" ]; then
    echo ""
    echo -e "${RED}LOAD_RATE=0: connections arrive as one burst — stress mode.${NC}"
    echo -e "${RED}Latency from this run includes SYN queueing; do not read it as a 0-RTT result.${NC}"
fi
echo ""

while IFS= read -r _input; do
    CONN=$((CONN + 1))
    echo -e "${GREEN}─── Flow #${CONN} (${LOAD_PORTS} ports, $LOAD_PARALLEL total) ──────────${NC}"
    python3 "$REPO_PATH/experiments/nodes/loadgen.py" --mode client \
        --host "$SERVER_IP" --port "$SERVER_PORT" --port-count "$LOAD_PORTS" \
        --parallel "$LOAD_PARALLEL" --bytes "$LOAD_BYTES" \
        --rate "$LOAD_RATE" --think-ms "$LOAD_THINK_MS" \
        --concurrency-limit "$LOAD_CONCURRENCY"
    echo ""
    echo "Press Enter for flow #$((CONN + 1)), or Ctrl+C to quit."
    echo ""
done
