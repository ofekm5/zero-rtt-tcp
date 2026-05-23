#!/bin/bash

# Function to extract the flow counter from a bridge
get_counter() {
  local bridge=$1
  local line=$2
  sudo ovs-ofctl dump-flows "$bridge" | cut -d"," -f4 | cut -d"=" -f2 | head -"$line" | tail -1
}

# Capture initial counters
br1_before=$(get_counter br1 2)
br2_req_before=$(get_counter br2 2)
br2_resp_before=$(get_counter br2 3)
br3_resp_before=$(get_counter br3 3)
br3_req_before=$(get_counter br3 2)

# Wait for user key press
read -n 1 -s -r -p "Press any key to continue..."

# Capture counters again
br1_after=$(get_counter br1 2)
br2_req_after=$(get_counter br2 2)
br2_resp_after=$(get_counter br2 3)
br3_resp_after=$(get_counter br3 3)
br3_req_after=$(get_counter br3 2)


# Compute and display differences
echo
echo "=== Flow Counter Differences ==="
echo "br2 to ARM (DNS Requests):        $((br2_req_after - br2_req_before))"
echo "DNS server to br3 (DNS Responses):  $((br3_resp_after - br3_resp_before))"
echo "br1 to ARM (DNS Responses):       $((br1_after - br1_before))"
echo "ARM to br2 (Filtered Responses):  $((br2_resp_after - br2_resp_before))"
