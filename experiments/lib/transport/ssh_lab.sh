#!/usr/bin/env bash
# SSH-gateway transport for the RUNS lab (Proxmox cluster).
#
# Provides the same interface as ssm.sh but executes commands over SSH
# through the RUNS gateway jump host at 132.75.121.140.
#
# All lab VMs are on the 10.13.37.0/24 dev subnet and are reachable only
# via the gateway (OpenVPN is unavailable; see .claude/skills/runs-lab-connect/).
#
# Prerequisites:
#   - F5 VPN (HAIFA) active
#   - ~/.ssh/config entry for "runs-gateway" pointing to 132.75.121.140
#     (or LAB_GATEWAY env var set to user@host)
#   - SSH key-based auth to gateway + lab VMs, OR SSH agent with passphrase-
#     protected key loaded (no interactive password prompts)
#   - python3 in PATH (local, for json_idx / mk_params)
#
# VM name → IP map (override via env, e.g. LAB_CLIENT_IP=10.13.37.X):
#   LAB_CLIENT_IP    (default: 10.13.37.10)
#   LAB_CLIENTNIC_IP (default: 10.13.37.11)
#   LAB_SERVERNIC_IP (default: 10.13.37.12)
#   LAB_SERVER_IP    (default: 10.13.37.13)
#   LAB_VM_USER      (default: root)
#   LAB_GATEWAY      (default: runs@132.75.121.140)
#   LAB_SSH_OPTS     (default: -o StrictHostKeyChecking=no -o ConnectTimeout=10
#                               -o BatchMode=yes)

# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v ssh &>/dev/null; then
    echo "ERROR: ssh is required" >&2; exit 1
fi
if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 is required" >&2; exit 1
fi

# ─── Configuration ────────────────────────────────────────────────────────────
LAB_GATEWAY="${LAB_GATEWAY:-runs@132.75.121.140}"
LAB_VM_USER="${LAB_VM_USER:-root}"
LAB_SSH_OPTS="${LAB_SSH_OPTS:--o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes}"

# Default IP assignments for the 4-VM chain in the RUNS lab dev subnet.
# Override these env vars before sourcing ssh_lab.sh if your lab uses different IPs.
LAB_CLIENT_IP="${LAB_CLIENT_IP:-10.13.37.10}"
LAB_CLIENTNIC_IP="${LAB_CLIENTNIC_IP:-10.13.37.11}"
LAB_SERVERNIC_IP="${LAB_SERVERNIC_IP:-10.13.37.12}"
LAB_SERVER_IP_INTERNAL="${LAB_SERVER_IP_INTERNAL:-10.13.37.13}"

# ─── JSON helpers (same as ssm.sh) ───────────────────────────────────────────
# These are needed by core.sh's json_idx calls on remote_run output.
# remote_run in ssh_lab.sh emits JSON [status, stdout, stderr] so json_idx works.

mk_params() { :; }  # not used in SSH transport; defined for source compatibility

# Extract element N from a JSON array on stdin
json_idx() {
    python3 -c "import json,sys; raw=sys.stdin.buffer.read(); v=json.loads(raw.decode('utf-8','replace'))[$1]; print(v.encode('ascii','replace').decode('ascii') if isinstance(v,str) else v, end='')"
}

# ─── Internal SSH helper ──────────────────────────────────────────────────────
# _lab_ssh <vm-ip> <command> [timeout-sec]
# Runs command on vm-ip via the gateway jump host.
# Returns [exit-code, stdout, stderr] as JSON (matching ssm.sh's json_idx contract).
_lab_ssh() {
    local vm_ip="$1" cmd="$2" timeout="${3:-120}"
    local stdout stderr rc

    stdout=$(ssh $LAB_SSH_OPTS \
        -J "$LAB_GATEWAY" \
        -o "ServerAliveInterval=10" \
        "${LAB_VM_USER}@${vm_ip}" \
        "timeout ${timeout} bash -c $(printf '%q' "$cmd") 2>/tmp/_lab_stderr_$$; cat /tmp/_lab_stderr_$$ >/dev/null" \
        2>/tmp/_lab_ssh_stderr_$$ || true
    )
    stderr=$(cat /tmp/_lab_ssh_stderr_$$ 2>/dev/null || true)
    rm -f /tmp/_lab_ssh_stderr_$$

    # Wrap in JSON matching ssm.sh's [Status, Stdout, Stderr] contract.
    # Status: "Success" when exit 0, "Failed" otherwise (mirrors SSM convention).
    if [[ $? -eq 0 ]]; then
        rc="Success"
    else
        rc="Failed"
    fi

    python3 -c "
import json, sys
status, stdout, stderr = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps([status, stdout, stderr]))
" "$rc" "$stdout" "$stderr"
}

# _lab_ssh_bg <vm-ip> <command>
# Fire-and-forget: starts command on vm-ip in background via gateway, returns immediately.
_lab_ssh_bg() {
    local vm_ip="$1" cmd="$2"
    ssh $LAB_SSH_OPTS \
        -J "$LAB_GATEWAY" \
        -o "ServerAliveInterval=10" \
        "${LAB_VM_USER}@${vm_ip}" \
        "nohup bash -c $(printf '%q' "$cmd") </dev/null >/dev/null 2>&1 &" \
        &>/dev/null &
}

# ─── Transport API (mirrors ssm.sh) ──────────────────────────────────────────

# remote_run <node-id> <command> [timeout-sec]
# node-id is the internal VM IP (populated by discover_nodes).
remote_run() {
    local node_id="$1" cmd="$2" timeout="${3:-120}"
    _lab_ssh "$node_id" "$cmd" "$timeout"
}

# remote_bg <node-id> <command>
remote_bg() {
    local node_id="$1" cmd="$2"
    _lab_ssh_bg "$node_id" "$cmd"
}

# remote_stdout <node-id> <command> [timeout-sec]
remote_stdout() {
    remote_run "$1" "$2" "${3:-120}" | json_idx 1
}

# ─── Node discovery ───────────────────────────────────────────────────────────
# Populates the global node-ID variables expected by core.sh.
# In SSH transport, node-IDs are IP addresses; no dynamic discovery needed.
# Override the LAB_*_IP env vars above for different lab topologies.
discover_nodes() {
    CLIENT_ID="$LAB_CLIENT_IP"
    CLIENTNIC_ID="$LAB_CLIENTNIC_IP"
    SERVERNIC_ID="$LAB_SERVERNIC_IP"
    SERVER_ID="$LAB_SERVER_IP_INTERNAL"
    SERVER_IP="$LAB_SERVER_IP_INTERNAL"

    # Validate reachability of each node via the gateway.
    local node ok=1
    for node in "$CLIENT_ID" "$CLIENTNIC_ID" "$SERVERNIC_ID" "$SERVER_ID"; do
        if ! ssh $LAB_SSH_OPTS -J "$LAB_GATEWAY" \
             "${LAB_VM_USER}@${node}" "true" &>/dev/null; then
            echo "ERROR: cannot reach lab VM $node via gateway $LAB_GATEWAY" >&2
            ok=0
        fi
    done
    [[ "$ok" -eq 1 ]] || return 1
}

# ─── MAC discovery ────────────────────────────────────────────────────────────
# In AWS, MACs come from the EC2 API.  In the Proxmox lab the MACs are read
# directly from the VMs via /sys/class/net/<iface>/address.
#
# get_lab_mac <vm-ip> <iface>
# Returns the MAC address of <iface> on the given VM.
get_lab_mac() {
    local vm_ip="$1" iface="$2"
    remote_stdout "$vm_ip" "cat /sys/class/net/${iface}/address 2>/dev/null || echo UNKNOWN"
}
