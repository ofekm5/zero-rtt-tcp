#!/usr/bin/env bash
# SSH transport for the two eswitch-offload-probe hosts:
#   - the BlueField-3 DPU ARM (bluefield-runs3-dpu)
#   - the x86 host VM that owns the ConnectX-7 PF (bluefield-dev)
#
# Reached directly over the RUNS lab OpenVPN tunnel (raw-IP routing, no
# gateway jump host) using the existing claude_code_ed25519 key.
#
# Usage (after sourcing):
#   dpu_run "ovs-vsctl show"
#   vm_run "ip link show ens16f0np0"

DPU_HOST="${DPU_HOST:-10.13.36.16}"
DPU_USER="${DPU_USER:-ubuntu}"
VM_HOST="${VM_HOST:-10.13.37.10}"
VM_USER="${VM_USER:-bluefieldadmin}"
PROBE_SSH_KEY="${PROBE_SSH_KEY:-$HOME/.ssh/claude_code_ed25519}"
PROBE_SSH_OPTS="${PROBE_SSH_OPTS:--o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10}"

# _probe_ssh <user> <host> <command>
# Runs command on host as user, using the probe SSH key. Returns the
# remote command's exit status.
_probe_ssh() {
    local user="$1" host="$2" cmd="$3"
    ssh -i "$PROBE_SSH_KEY" $PROBE_SSH_OPTS "${user}@${host}" -- "$cmd"
}

# dpu_run <command>
# Runs command on the DPU ARM (DPU_HOST as DPU_USER). Returns remote exit status.
dpu_run() {
    _probe_ssh "$DPU_USER" "$DPU_HOST" "$1"
}

# vm_run <command>
# Runs command on the x86 host VM (VM_HOST as VM_USER). Returns remote exit status.
vm_run() {
    _probe_ssh "$VM_USER" "$VM_HOST" "$1"
}
