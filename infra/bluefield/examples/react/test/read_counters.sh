#!/bin/bash

# === Script Name ===
# measure_flow_counters.sh
#
# === Description ===
# This script measures and reports packet-level flow counters on two network interfaces
# (ens5f0np0 and ens5f1np1) before and after a short measurement interval.
#
# It captures RX and TX packet counts on both interfaces using `ifconfig`,
# waits for a key press (during which some activity or experiment may run),
# and then prints the difference in counters.
#
# This allows users to interactively measure the volume of transmitted and received
# packets on each interface within a defined time window.
#
# === Usage ===
# ./measure_flow_counters.sh
# → Press any key when prompted to mark the end of the measurement interval.
#
# === Requirements ===
# - Interface names `ens5f0np0` and `ens5f1np1` must exist and be active
# - Requires `ifconfig` (from `net-tools`) to be installed
#
# === Notes ===
# - Output differences represent packet-level traffic over the interval
# - Useful for validating behavior of experiments, services, or packet generators
# Function to extract the flow counter from an interface

get_counter() {
  local interface=$1
  local type=$2
  ifconfig $interface| grep "$type packets" | cut -d" " -f11
}

# Capture initial counters
i0_rx_before=$(get_counter ens5f0np0 RX)
i0_tx_before=$(get_counter ens5f0np0 TX)
i1_rx_before=$(get_counter ens5f1np1 RX)
i1_tx_before=$(get_counter ens5f1np1 TX)

# Wait for user key press
read -n 1 -s -r -p "Press any key to continue..."

# Capture counters again
i0_rx_after=$(get_counter ens5f0np0 RX)
i0_tx_after=$(get_counter ens5f0np0 TX)
i1_rx_after=$(get_counter ens5f1np1 RX)
i1_tx_after=$(get_counter ens5f1np1 TX)



# Compute and display differences
echo
echo "=== Flow Counter Differences ==="
echo "Outgoing DNS Requests:        $((i0_tx_after - i0_tx_before))"
echo "Incoming DNS Requests to BIND9:  $((i1_rx_after - i1_rx_before))"
echo "Outgoing DNS Responses from BIND9 and attack:       $((i1_tx_after - i1_tx_before))"
echo "Incoming DNS Responses:  $((i0_rx_after - i0_rx_before))"
