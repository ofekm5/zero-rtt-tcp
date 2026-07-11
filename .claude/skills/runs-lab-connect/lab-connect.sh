#!/usr/bin/env bash
# RUNS Lab connection helper
# Usage: ./lab-connect.sh <command> [args]
#   ./lab-connect.sh status             # Check whether the lab OpenVPN tunnel is up
#   ./lab-connect.sh ssh 10.13.37.5     # SSH directly into an internal VM (root by default)
#   ./lab-connect.sh ssh 10.13.37.5 alice
#   ./lab-connect.sh help               # full reference
#
# Prerequisite: connect the `runs` OpenVPN profile (imported from runs.ovpn in this folder)
# in your OpenVPN client first. Once connected, internal lab IPs are reachable directly —
# no gateway jump host or port forwarding needed.

PROBE_IP="10.13.35.1"  # pfSense, used as a liveness check for the VPN tunnel

cmd_status() {
    echo "Checking lab VPN connectivity (probing $PROBE_IP)..."
    if ping -n 1 -w 1500 "$PROBE_IP" >/dev/null 2>&1 || ping -c 1 -W 1 "$PROBE_IP" >/dev/null 2>&1; then
        echo "VPN appears connected — $PROBE_IP is reachable."
    else
        echo "Cannot reach $PROBE_IP. Open your OpenVPN client and connect the 'runs' profile"
        echo "(imported from .claude/skills/runs-lab-connect/runs.ovpn), then retry."
        exit 1
    fi
}

# ssh <internal-ip> [user]
# Example: ./lab-connect.sh ssh 10.13.37.5 root
cmd_ssh() {
    local remote_ip="$1"
    local remote_user="${2:-root}"

    if [[ -z "$remote_ip" ]]; then
        echo "Usage: $0 ssh <internal-ip> [user]"
        echo "Example: $0 ssh 10.13.37.5 root"
        exit 1
    fi

    echo "Connecting to $remote_user@$remote_ip (direct, via lab VPN)..."
    ssh "${remote_user}@${remote_ip}"
}

cmd_help() {
    cat <<EOF
RUNS Lab connection helper

Commands:
  status                    Check whether the lab OpenVPN tunnel is up
  ssh <internal-ip> [user]  SSH directly into an internal VM (default user: root)

Prerequisite:
  Connect the 'runs' OpenVPN profile (imported from runs.ovpn in this skill folder)
  in your OpenVPN client. Once connected, internal lab IPs are reachable directly —
  no gateway jump host, no SSH tunneling.

Common internal IPs:
  Dev VMs      10.13.37.x   (unrestricted internet, free-use)
  Prod/NICs    10.13.36.x   (hardware NICs, Tofino, Bluefield)
  Management   10.13.35.x   (pfSense, Bitwarden)

Proxmox UIs (direct, once VPN is connected):
  runs1  https://132.75.121.131
  runs2  https://132.75.121.132
  runs3  https://132.75.121.133
  runs4  https://132.75.121.134

Credentials: https://gitlab.com/runs-lab/common/-/wikis/Login-(New)
EOF
}

case "${1:-help}" in
    status)  cmd_status ;;
    ssh)     cmd_ssh "$2" "$3" ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
