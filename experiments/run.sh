#!/usr/bin/env bash
# Single entrypoint for the experiment harness.
#
#   STACK      0rtt (default) | baseline — the 0-RTT DPDK data plane, or plain
#              kernel-forwarded TCP (infra/baseline) to compare it against
#   TRANSPORT  ssm  (default) | ssh      — AWS SSM, or the RUNS Proxmox lab over
#              the SSH gateway (see experiments/lib/transport/ssh_lab.sh)
#
# Load knobs (CONNECTIONS, LOAD_*, NETEM_RTT_MS, REPO_REF) are read as before —
# see experiments/lib/measure.sh and experiments/lib/endpoint.sh.
#
# Usage:
#   ./experiments/run.sh
#   STACK=baseline ./experiments/run.sh
#   TRANSPORT=ssh CONNECTIONS=10 ./experiments/run.sh
#
# Exit code: 0 = all checks passed, non-zero = number of failures

set -uo pipefail

# Force UTF-8 I/O for the AWS CLI (also Python) so non-ASCII chars in VM log
# output (em-dashes, arrows) don't cause cp1252 encode errors on Windows.
export PYTHONUTF8=1
export PYTHONIOENCODING=utf-8

STACK="${STACK:-0rtt}"
TRANSPORT="${TRANSPORT:-ssm}"

# Validate both before sourcing anything: a transport shim is the first thing
# that can reach a remote, so a typo must stop here.
case "$STACK" in
    0rtt|baseline) ;;
    *) echo "ERROR: unrecognised STACK='$STACK' — accepted values: 0rtt, baseline" >&2; exit 2 ;;
esac
case "$TRANSPORT" in
    ssm) REPO_PATH="/home/ec2-user/zero-rtt-tcp" ;;
    ssh) REPO_PATH="/home/user/zero-rtt-tcp" ;;
    *) echo "ERROR: unrecognised TRANSPORT='$TRANSPORT' — accepted values: ssm, ssh" >&2; exit 2 ;;
esac
# The lab is static DPDK VMs, not IaC — there is no baseline stack to reach over
# ssh, and running the baseline flow there would leave routes/netem on shared VMs.
if [[ "$STACK" == baseline && "$TRANSPORT" == ssh ]]; then
    echo "ERROR: STACK=baseline is AWS-only (TRANSPORT=ssm) — the lab has no baseline stack" >&2
    exit 2
fi

SERVER_PORT=8080
# Measurement ROUNDS (each round opens LOAD_PARALLEL connections across
# LOAD_PORTS ports — see experiments/lib/measure.sh). Default 1 round.
CONNECTIONS="${CONNECTIONS:-1}"
FAILURES=0

# The five MACs run_experiment takes. Only the 0-RTT prologue resolves them;
# baseline has no data plane and passes them empty.
GW_MAC="" CLIENTNIC_ETH1_MAC="" SERVER_ETH0_MAC="" CLIENTNIC_ETH2_MAC="" SERVERNIC_ETH2_MAC=""

if [[ "$TRANSPORT" == ssm ]]; then
    # shellcheck source=lib/transport/ssm.sh
    source "$(dirname "$0")/lib/transport/ssm.sh"

    remote_run()    { ssm_run    "$@"; }
    remote_bg()     { ssm_bg     "$@"; }
    remote_stdout() { ssm_stdout "$@"; }

    # SSM silently truncates StandardOutputContent at 24 KB — no error, no marker.
    # core.sh uses this to warn when a fetched blob lands at the cap.
    REMOTE_OUTPUT_CAP=24000

    # Populates SERVER_ID, SERVERNIC_ID, CLIENTNIC_ID, CLIENT_ID, SERVER_IP from
    # the EC2 Name tags of the chosen stack (infra/dpdk: smartnics-*,
    # infra/baseline: baseline-*).
    discover_nodes() {
        local p=smartnics
        [[ "$STACK" == baseline ]] && p=baseline
        SERVER_ID=$(get_iid "$p-server")
        SERVERNIC_ID=$(get_iid "$p-servernic")
        CLIENTNIC_ID=$(get_iid "$p-clientnic")
        CLIENT_ID=$(get_iid "$p-client")
        SERVER_IP=$(get_ip "$p-server")
    }

    # ec2_mac <name-tag> <device-index> — MAC of that ENI, from the EC2 API.
    # The DPDK-bound ports can't be ARPed, so the API is the only source.
    ec2_mac() {
        aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
            --query "Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==\`$2\`].MacAddress" \
            --output text --region eu-central-1 2>/dev/null | tr -d '[:space:]'
    }

    # 0-RTT prologue: resolve the MACs from the EC2 API, then smoke-test the
    # ClientNIC forwarder (run 3 s, check it reached busy-poll).
    prologue_0rtt() {
        log "Resolving Ethernet MACs from EC2 API..."
        GW_MAC=$(ec2_mac smartnics-servernic 1)              # ServerNIC eth1 → ClientNIC --gw-mac
        CLIENTNIC_ETH1_MAC=$(ec2_mac smartnics-clientnic 1)  # → ServerNIC --gw-mac
        SERVER_ETH0_MAC=$(ec2_mac smartnics-server 0)        # → ServerNIC --server-mac
        CLIENTNIC_ETH2_MAC=$(ec2_mac smartnics-clientnic 2)  # ClientNIC's own client-facing port
        SERVERNIC_ETH2_MAC=$(ec2_mac smartnics-servernic 2)  # ServerNIC's own server-facing port

        log "  ClientNIC eth1 MAC (ServerNIC --gw-mac):          ${CLIENTNIC_ETH1_MAC:-UNKNOWN}"
        log "  Server eth0 MAC (ServerNIC --server-mac):         ${SERVER_ETH0_MAC:-UNKNOWN}"
        log "  ClientNIC eth2 MAC (its own client-facing port):  ${CLIENTNIC_ETH2_MAC:-UNKNOWN}"
        log "  ServerNIC eth2 MAC (its own server-facing port):  ${SERVERNIC_ETH2_MAC:-UNKNOWN}"

        local _v
        for _v in CLIENTNIC_ETH1_MAC SERVER_ETH0_MAC CLIENTNIC_ETH2_MAC SERVERNIC_ETH2_MAC; do
            if [[ -z "${!_v}" || "${!_v}" == "None" ]]; then
                fail "Could not resolve $_v from the EC2 API"
            fi
        done

        if [[ -z "$GW_MAC" || "$GW_MAC" == "None" ]]; then
            fail "Smoke test: could not discover ServerNIC eth1 MAC (DeviceIndex=1)"
            return
        fi
        log "  Gateway MAC (ServerNIC eth1, DPDK port): $GW_MAC"

        local BINARY="$REPO_PATH/src/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder"
        remote_run "$CLIENTNIC_ID" \
            "rm -f /tmp/clientnic_smoke.log; \
             setsid $BINARY -l 0 -- --port=$SERVER_PORT --gw-mac=$GW_MAC \
                 --client-port-mac=$CLIENTNIC_ETH2_MAC --server-port-mac=$CLIENTNIC_ETH1_MAC \
                 < /dev/null > /tmp/clientnic_smoke.log 2>&1 & \
             BPID=\$!; sleep 3; kill \$BPID 2>/dev/null; wait \$BPID 2>/dev/null; true" \
            30 > /dev/null

        local SMOKE_LOG
        SMOKE_LOG=$(remote_stdout "$CLIENTNIC_ID" "cat /tmp/clientnic_smoke.log 2>/dev/null || echo MISSING" 30)
        echo "--- ClientNIC forwarder smoke log ---"
        echo "$SMOKE_LOG"
        echo "-------------------------------------"

        if echo "$SMOKE_LOG" | grep -qiE "busy-poll loop|Entering busy-poll"; then
            pass "Smoke test: clientnic-dpdk-forwarder entered busy-poll loop"
        elif echo "$SMOKE_LOG" | grep -qiE "port.*started|DPDK.*start"; then
            pass "Smoke test: clientnic-dpdk-forwarder DPDK port initialised"
        elif echo "$SMOKE_LOG" | grep -qiE "EAL.*FATAL|Cannot create lock|EAL init failed"; then
            fail "Smoke test: clientnic-dpdk-forwarder EAL init failed (stale DPDK lock?)"
        else
            fail "Smoke test: clientnic-dpdk-forwarder did not reach expected startup state"
        fi
    }
else
    # Defines remote_run/remote_bg/remote_stdout, discover_nodes and get_lab_mac.
    # shellcheck source=lib/transport/ssh_lab.sh
    source "$(dirname "$0")/lib/transport/ssh_lab.sh"

    # 0-RTT prologue: no EC2 API in the lab, so read the MACs off the VMs.
    prologue_0rtt() {
        log "Resolving Ethernet MACs from lab VMs..."
        GW_MAC=$(get_lab_mac "$SERVERNIC_ID" "eth1")
        CLIENTNIC_ETH1_MAC=$(get_lab_mac "$CLIENTNIC_ID" "eth1")
        SERVER_ETH0_MAC=$(get_lab_mac "$SERVER_ID" "eth0")
        CLIENTNIC_ETH2_MAC=$(get_lab_mac "$CLIENTNIC_ID" "eth2")
        SERVERNIC_ETH2_MAC=$(get_lab_mac "$SERVERNIC_ID" "eth2")

        local _v
        for _v in GW_MAC CLIENTNIC_ETH1_MAC SERVER_ETH0_MAC CLIENTNIC_ETH2_MAC SERVERNIC_ETH2_MAC; do
            log "  $_v: ${!_v:-UNKNOWN}"
            if [[ -z "${!_v}" || "${!_v}" == "UNKNOWN" ]]; then
                echo -e "${RED}ERROR: could not resolve $_v${NC}" >&2
                exit 1
            fi
        done
    }
fi

# shellcheck source=lib/measure.sh
source "$(dirname "$0")/lib/measure.sh"
# shellcheck source=lib/output.sh
source "$(dirname "$0")/lib/output.sh"
# shellcheck source=lib/core.sh
source "$(dirname "$0")/lib/core.sh"
# shellcheck source=lib/report.sh
source "$(dirname "$0")/lib/report.sh"


# ─── Step 0: Discover nodes ───────────────────────────────────────────────────
log "Step 0: Discovering $STACK nodes over $TRANSPORT..."

if ! discover_nodes; then
    echo -e "${RED}ERROR: one or more nodes are unreachable over $TRANSPORT${NC}" >&2
    exit 1
fi

log "  Server:    $SERVER_ID  ($SERVER_IP)"
log "  ServerNIC: $SERVERNIC_ID"
log "  ClientNIC: $CLIENTNIC_ID"
log "  Client:    $CLIENT_ID"

for var in SERVER_ID SERVERNIC_ID CLIENTNIC_ID CLIENT_ID SERVER_IP; do
    if [[ -z "${!var}" || "${!var}" == "None" ]]; then
        echo -e "${RED}ERROR: could not find running node for $var (is the $STACK stack deployed?)${NC}" >&2
        exit 1
    fi
done

[[ "$STACK" == 0rtt ]] && prologue_0rtt


# ─── Run shared experiment core ───────────────────────────────────────────────
run_experiment "$GW_MAC" "$CLIENTNIC_ETH1_MAC" "$SERVER_ETH0_MAC" \
               "$CLIENTNIC_ETH2_MAC" "$SERVERNIC_ETH2_MAC"


# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}  ALL CHECKS PASSED${NC}"
else
    echo -e "${RED}  $FAILURES CHECK(S) FAILED${NC}"
fi
echo "════════════════════════════════════════"


# ─── Write report ─────────────────────────────────────────────────────────────
write_run_report "$STACK" "$TRANSPORT"

exit "$FAILURES"
