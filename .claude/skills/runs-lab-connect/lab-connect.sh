#!/usr/bin/env bash
# RUNS Lab connection helper
# Usage: ./lab-connect.sh <command> [args]
#   ./lab-connect.sh setup              # [ONLY ONCE] Write ~/.ssh/config entry
#   ./lab-connect.sh connect            # SSH into gateway
#   ./lab-connect.sh jump 10.13.37.5    # SSH to internal VM via jump
#   ./lab-connect.sh tunnel 10.13.37.5 443 8443  # port-forward to internal service
#   ./lab-connect.sh help               # full reference

GATEWAY_IP="132.75.121.140"
GATEWAY_USER="runs"
SSH_CONFIG="$HOME/.ssh/config"
SSH_ENTRY="Host runs-gateway
  HostName $GATEWAY_IP
  User $GATEWAY_USER"

cmd_setup() {
    if grep -q "Host runs-gateway" "$SSH_CONFIG" 2>/dev/null; then
        echo "runs-gateway entry already exists in $SSH_CONFIG"
    else
        printf "\n%s\n" "$SSH_ENTRY" >> "$SSH_CONFIG"
        echo "Added runs-gateway to $SSH_CONFIG"
    fi
}

cmd_connect() {
    echo "Connecting to RUNS gateway ($GATEWAY_USER@$GATEWAY_IP)..."
    ssh runs-gateway
}

# tunnel <internal-ip> <internal-port> [local-port]
# Example: ./lab-connect.sh tunnel 10.13.37.5 443 8443
cmd_tunnel() {
    local remote_ip="$1"
    local remote_port="$2"
    local local_port="${3:-$remote_port}"

    if [[ -z "$remote_ip" || -z "$remote_port" ]]; then
        echo "Usage: $0 tunnel <internal-ip> <remote-port> [local-port]"
        echo "Example: $0 tunnel 10.13.37.5 443 8443"
        exit 1
    fi

    echo "Forwarding localhost:$local_port → $remote_ip:$remote_port via gateway"
    echo "Browse: http(s)://localhost:$local_port"
    ssh -L "${local_port}:${remote_ip}:${remote_port}" runs-gateway -N
}

# jump <internal-ip> [user]
# Example: ./lab-connect.sh jump 10.13.37.5 root
cmd_jump() {
    local remote_ip="$1"
    local remote_user="${2:-root}"

    if [[ -z "$remote_ip" ]]; then
        echo "Usage: $0 jump <internal-ip> [user]"
        echo "Example: $0 jump 10.13.37.5 root"
        exit 1
    fi

    echo "Jumping to $remote_user@$remote_ip via gateway..."
    ssh -J runs-gateway "${remote_user}@${remote_ip}"
}

cmd_help() {
    cat <<EOF
RUNS Lab connection helper

Commands:
  setup                         Add runs-gateway entry to ~/.ssh/config
  connect                       SSH into the gateway (runs@$GATEWAY_IP)
  jump   <internal-ip> [user]   SSH to an internal VM via gateway jump host
  tunnel <internal-ip> <port> [local-port]
                                Forward a local port to an internal service

Common internal IPs:
  Dev VMs      10.13.37.x   (unrestricted internet, free-use)
  Prod/NICs    10.13.36.x   (hardware NICs, Tofino, Bluefield)
  Management   10.13.35.x   (pfSense, Bitwarden)

Proxmox UIs (direct, F5 VPN required):
  runs1  https://132.75.121.131
  runs2  https://132.75.121.132
  runs3  https://132.75.121.133
  runs4  https://132.75.121.134

Prerequisites: F5 VPN (HAIFA) must be connected first.
Credentials: https://gitlab.com/runs-lab/common/-/wikis/Login-(New)
EOF
}

case "${1:-help}" in
    setup)   cmd_setup ;;
    connect) cmd_connect ;;
    tunnel)  cmd_tunnel "$2" "$3" "$4" ;;
    jump)    cmd_jump "$2" "$3" ;;
    help|--help|-h) cmd_help ;;
    *)
        echo "Unknown command: $1"
        cmd_help
        exit 1
        ;;
esac
