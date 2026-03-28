#!/usr/bin/env bash
# Open an interactive SSM terminal session into a 0-RTT demo VM.
#
# Run this in 4 separate local terminals, one per node, then run the
# appropriate node script inside each SSM session:
#
#   Scapy stack: bash ~/zero-rtt-demo/experiments/zero-rtt-clientnic-translate/nodes/<node>.sh
#   DPDK stack:  bash ~/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/<node>.sh
#
# Startup order: server → servernic → clientnic → client
#
# Usage: ./experiments/ssm-login.sh <node>
#   node: server | servernic | clientnic | client

set -euo pipefail

REGION="eu-central-1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

NODE="${1:-}"

declare -A TAG_MAP=(
    [server]="smartnics-server"
    [servernic]="smartnics-servernic"
    [clientnic]="smartnics-clientnic"
    [client]="smartnics-client"
)

if [ -z "$NODE" ] || [ -z "${TAG_MAP[$NODE]:-}" ]; then
    echo "Usage: $0 <node>"
    echo "  node: server | servernic | clientnic | client"
    echo ""
    echo "Open 4 terminals and run one per node in startup order:"
    echo "  $0 server"
    echo "  $0 servernic"
    echo "  $0 clientnic"
    echo "  $0 client"
    exit 1
fi

if ! command -v aws &>/dev/null; then
    echo -e "${RED}ERROR: aws CLI is required${NC}" >&2
    exit 1
fi

TAG="${TAG_MAP[$NODE]}"
echo -e "${YELLOW}Looking up instance for '${NODE}' (tag: ${TAG})...${NC}"

IID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$TAG" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text --region "$REGION")

if [ -z "$IID" ] || [ "$IID" = "None" ]; then
    echo -e "${RED}ERROR: No running instance found with tag Name=${TAG}${NC}" >&2
    exit 1
fi

echo -e "${GREEN}Connecting to ${NODE} (${IID})...${NC}"
echo ""
echo -e "${CYAN}Once connected, run the node script (pick your stack):${NC}"
echo "  Scapy: bash ~/zero-rtt-demo/experiments/zero-rtt-clientnic-translate/nodes/${NODE}.sh"
echo "  DPDK:  bash ~/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/${NODE}.sh"
echo ""

aws ssm start-session --target "$IID" --region "$REGION"
