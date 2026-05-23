#!/bin/bash

#
# === Description ===
# This script uses `tc` (Traffic Control) to apply artificial delay to DNS response packets
# originating from a specific source IP (default: 192.168.5.11) on a given interface
# (default: ens5f1np1).
#
# The delay is applied only to packets with:
# - UDP source port 53 (DNS responses)
# - Source IP matching $SRC_IP
# - Matching interface $IFACE
#
# All other traffic is passed through an unaffected fast path.
# The delay is implemented via the `netem` qdisc with a normal distribution (±10ms jitter).
#
# === Usage ===
# ./delay_dns_responses.sh <delay_ms>
#
# - <delay_ms>: Mean delay in milliseconds to apply to DNS responses (required)
#
# === Notes ===
# - The script cleans any existing qdisc setup on $IFACE before applying new rules.
# - Rules are removed once a key is pressed.
# - Requires sudo permissions for `tc` commands.
#
# === Example ===
# .delay_dns_responses..sh 40
# → Applies 40ms ±10ms delay to DNS responses from 192.168.5.11 on ens5f1np1

if [ $# -ne 1 ]; then
  echo "Usage: $0 <delay_ms>"
  exit 1
fi

DELAY="$1"
IFACE="ens5f1np1"
SRC_IP="192.168.5.11"

echo "[+] Applying $DELAY ms delay to DNS responses from $SRC_IP on $IFACE"

# Clean any existing qdisc
sudo tc qdisc del dev $IFACE root 2>/dev/null

# Root qdisc
sudo tc qdisc add dev $IFACE root handle 1: htb default 20

# Fast path: class for all other traffic (no delay)
sudo tc class add dev $IFACE parent 1: classid 1:20 htb rate 10000mbit ceil 10000mbit

# Delayed path: class for DNS responses
sudo tc class add dev $IFACE parent 1: classid 1:10 htb rate 1000mbit ceil 1000mbit

# Add netem delay to DNS response class
sudo tc qdisc add dev $IFACE parent 1:10 handle 10: netem delay ${DELAY}ms 10ms distribution normal limit 10000

# Filter for DNS responses (delayed path)
sudo tc filter add dev $IFACE protocol ip parent 1:0 prio 1 u32 \
  match ip src ${SRC_IP}/32 \
  match ip protocol 17 0xff \
  match ip sport 53 0xffff \
  flowid 1:10

# Optionally: wildcard filter to classify all other traffic into fast path
sudo tc filter add dev $IFACE protocol ip parent 1:0 prio 10 u32 \
  match u32 0 0 \
  flowid 1:20

echo "[+] Delay applied. Press any key to remove..."
read -n 1 -s

echo "[+] Cleaning up tc rules..."
sudo tc qdisc del dev $IFACE root
echo "[+] Done."
