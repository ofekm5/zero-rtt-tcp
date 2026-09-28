#!/usr/bin/env bash
# Shared SSM helpers for all experiment orchestrators.
# Source this file: source "$(dirname "$0")/../lib/transport/ssm.sh"

# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v aws &>/dev/null; then
    echo "ERROR: aws CLI is required" >&2; exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required" >&2; exit 1
fi

# ─── SSM helpers ──────────────────────────────────────────────────────────────

# Build SSM parameters JSON from a shell command string
mk_params() { python3 -c "import json,sys; print(json.dumps({'commands':[sys.argv[1]]}))" "$1"; }

# Extract element N from a JSON array on stdin (UTF-8-safe, handles non-ASCII in VM logs)
json_idx() { python3 -c "import json,sys; raw=sys.stdin.buffer.read(); v=json.loads(raw.decode('utf-8','replace'))[$1]; print(v.encode('ascii','replace').decode('ascii') if isinstance(v,str) else v, end='')"; }

# ssm_run <instance-id> <command> [timeout-sec]
# Runs a command synchronously via SSM. Returns JSON: [Status, Stdout, Stderr]
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
    # The `command-executed` waiter caps at ~100s (20 attempts x 5s), which is far
    # short of a 100000-connection round. Poll the invocation status ourselves up
    # to $timeout so long-running measurements run to completion before we read out.
    local waited=0 status
    while :; do
        status=$(aws ssm get-command-invocation \
            --command-id "$cid" --instance-id "$iid" \
            --query "Status" --output text --region eu-central-1 2>/dev/null || echo Pending)
        case "$status" in
            Success|Cancelled|TimedOut|Failed) break ;;
        esac
        [ "$waited" -ge "$timeout" ] && break
        sleep 5; waited=$((waited + 5))
    done
    aws ssm get-command-invocation \
        --command-id "$cid" \
        --instance-id "$iid" \
        --query "[Status, StandardOutputContent, StandardErrorContent]" \
        --output json --region eu-central-1
}

# ssm_stdout <instance-id> <command> [timeout-sec]
ssm_stdout() { ssm_run "$1" "$2" "${3:-120}" | json_idx 1; }

# ssm_bg <instance-id> <command>
# Fires a command in the background and returns immediately.
ssm_bg() {
    local iid="$1" cmd="$2"
    local params
    params=$(mk_params "$cmd")
    aws ssm send-command \
        --instance-ids "$iid" \
        --document-name "AWS-RunShellScript" \
        --parameters "$params" \
        --timeout-seconds 30 \
        --query "Command.CommandId" \
        --output text --region eu-central-1 > /dev/null
}

# ─── EC2 discovery ────────────────────────────────────────────────────────────
# Look up instance IDs and IPs by the Name tag. Always queries fresh since IPs
# change on every instance restart.

get_iid() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].InstanceId" \
        --output text --region eu-central-1
}

get_ip() {
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query "Reservations[0].Instances[0].PrivateIpAddress" \
        --output text --region eu-central-1
}
