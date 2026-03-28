#!/usr/bin/env bash
# Run DPDK unit tests on the ClientNIC VM via AWS SSM.
#
# Discovers the ClientNIC instance by EC2 tag, builds clientnic-dpdk on the VM,
# then runs the 5 DPDK smoke tests (virtual PMDs — no hardware required).
#
# Pattern mirrors run_experiment.sh: SSM over aws CLI, no SSH keys needed.
#
# Prerequisites (run locally):
#   - aws CLI configured with SSM access
#   - python3 in PATH
#   - ClientNIC VM running and reachable via SSM
#   - ~/zero-rtt-demo on the VM is up to date
#
# Usage:
#   ./experiments/zero-rtt-dpdk/run_dpdk_tests_ssm.sh
#
# Exit code: 0 = build + tests passed, non-zero = build or test failure

set -uo pipefail

REPO_PATH="/home/ec2-user/zero-rtt-demo"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

log()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $*${NC}" >&2; }
pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }

# Build SSM parameters JSON from a shell command string
mk_params() { python3 -c "import json,sys; print(json.dumps({'commands':[sys.argv[1]]}))" "$1"; }
# Extract element N from a JSON array on stdin
json_idx()  { python3 -c "import json,sys; print(json.load(sys.stdin)[$1], end='')"; }


# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
    echo "ERROR: aws CLI is required" >&2
    exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required" >&2
    exit 1
fi


# ─── SSM helper ───────────────────────────────────────────────────────────────

# ssm_run <instance-id> <command> [timeout-sec]
# Runs a command synchronously via SSM.
# Returns JSON array: [Status, Stdout, Stderr]
ssm_run() {
    local iid="$1" cmd="$2" timeout="${3:-120}"
    local params cid

    params=$(mk_params "$cmd")

    cid=$(aws ssm send-command \
        --instance-ids "$iid" \
        --document-name "AWS-RunShellScript" \
        --parameters "$params" \
        --timeout-seconds "$timeout" \
        --query "Command.CommandId" \
        --output text --region eu-central-1)

    aws ssm wait command-executed \
        --command-id "$cid" \
        --instance-id "$iid" --region eu-central-1 2>/dev/null || true

    aws ssm get-command-invocation \
        --command-id "$cid" \
        --instance-id "$iid" \
        --query "[Status, StandardOutputContent, StandardErrorContent]" \
        --output json --region eu-central-1
}


# ─── Discover ClientNIC instance ─────────────────────────────────────────────
log "Discovering ClientNIC instance..."

CLIENTNIC_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=smartnics-clientnic" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text --region eu-central-1)

if [[ -z "$CLIENTNIC_ID" || "$CLIENTNIC_ID" == "None" ]]; then
    echo -e "${RED}ERROR: could not find a running instance tagged smartnics-clientnic${NC}" >&2
    exit 1
fi

log "  ClientNIC: $CLIENTNIC_ID"


# ─── Build step ───────────────────────────────────────────────────────────────
log "Building clientnic-dpdk on VM..."
echo "--- Build output ---"

BUILD_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig && cd $REPO_PATH/clientnic/dpdk && meson setup builddir --wipe 2>&1 | tail -5 && ninja -C builddir 2>&1 | tail -10" \
    120)

BUILD_STATUS=$(echo "$BUILD_RESULT" | json_idx 0)
BUILD_STDOUT=$(echo "$BUILD_RESULT" | json_idx 1)
BUILD_STDERR=$(echo "$BUILD_RESULT" | json_idx 2)

echo "$BUILD_STDOUT"
[[ -n "$BUILD_STDERR" ]] && echo "stderr: $BUILD_STDERR"
echo "--------------------"

if [[ "$BUILD_STATUS" != "Success" ]]; then
    fail "Build failed (SSM status: $BUILD_STATUS)"
    exit 1
fi
pass "Build succeeded"


# ─── Test step ────────────────────────────────────────────────────────────────
log "Running DPDK tests on VM..."
echo "--- Test output ---"

TEST_RESULT=$(ssm_run "$CLIENTNIC_ID" \
    "sudo bash $REPO_PATH/clientnic/dpdk/tests/run_dpdk_tests.sh $REPO_PATH/clientnic/dpdk/builddir/clientnic-dpdk" \
    60)

TEST_STATUS=$(echo "$TEST_RESULT" | json_idx 0)
TEST_STDOUT=$(echo "$TEST_RESULT" | json_idx 1)
TEST_STDERR=$(echo "$TEST_RESULT" | json_idx 2)

echo "$TEST_STDOUT"
[[ -n "$TEST_STDERR" ]] && echo "stderr: $TEST_STDERR"
echo "-------------------"


# ─── Result ───────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [[ "$TEST_STATUS" == "Success" ]] && echo "$TEST_STDOUT" | grep -qE "0 failed"; then
    pass "DPDK tests passed"
    echo -e "${GREEN}  ALL TESTS PASSED${NC}"
    echo "════════════════════════════════════════"
    exit 0
else
    fail "DPDK tests failed (SSM status: $TEST_STATUS)"
    echo -e "${RED}  TESTS FAILED${NC}"
    echo "════════════════════════════════════════"
    exit 1
fi
