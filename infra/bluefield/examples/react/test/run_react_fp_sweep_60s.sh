#!/bin/bash

# === Description ===
# This script automates a performance experiment involving traffic replay and packet loss (in ReAct context: 
# false positives rate) measurement on a remote DPU using the DOCA Flow ReAct DOCA application.
#
# It connects to the DPU over SSH, runs the `react.sh` script with an increasing number of cores,
# captures traffic before and after processing using tcpdump, replays DNS traffic using tcpreplay for 60 
# seconds, and measures the packet loss ratio at each step.
#
# The loss ratios are recorded in a specified output file.
# The experiment terminates early if zero loss is observed or if packet capture fails.
#
# === Usage ===
# ./script_name.sh <output_file> [dpu_args...]
#
# - <output_file>: Path to store the results (required)
# - [dpu_args...]: Optional arguments passed directly to react.sh on the DPU
#
# === Requirements ===
# - Password-based SSH access to the DPU (no public key setup)
# - Sudo privileges on the local machine for tcpdump and tcpreplay
# - Interfaces ens5f0np0 and ens5f1np1 must exist and be connected appropriately
#
# === Notes ===
# - Temporary askpass scripts are used to automate password entry
# - Captured packets are filtered by UDP port 53 and source IP 192.168.5.11
# - Replay uses a random window from `dns1M.pcap` trimmed to 60,000 packets. This can be created using make_dns_pcap_1M.py
# - Results are printed in green and saved to the output file

DPU_USER=ubuntu
DPU_HOST=192.168.27.3
DPU_BASE_DIR=/home/ubuntu/sources/dh2156/samples/doca_flow/react


# === Output file from first argument ===
if [[ -z "$1" ]]; then
  echo "Usage: $0 <output_file> [dpu_args...]"
  exit 1
fi

OUTPUT_FILE="$1"
shift  # Remove the first argument, so $@ now holds only DPU_ARGS
DPU_ARGS=("$@")

# Prompt once for sudo password and configure askpass
read -s -p "Enter sudo password: " SUDO_PASS
echo
export SUDO_ASKPASS=$(mktemp)
echo -e "#!/bin/bash\necho '$SUDO_PASS'" > "$SUDO_ASKPASS"
chmod +x "$SUDO_ASKPASS"

# Prompt once for DPU SSH password and create askpass script
read -s -p "Enter DPU password: " DPU_PASS
echo
DPU_ASKPASS=$(mktemp)
echo -e "#!/bin/bash\necho '$DPU_PASS'" > "$DPU_ASKPASS"
chmod +x "$DPU_ASKPASS"

trap "rm -f $SUDO_ASKPASS $DPU_ASKPASS responses_before_*.pcap responses_after_*.pcap trimmed.pcap" EXIT

for ((i=0; i<15; i++)); do
  CORES=$((i + 1))

  # Start react.sh on the DPU
  DISPLAY=:0 SSH_ASKPASS=$DPU_ASKPASS setsid ssh -tt \
    -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no \
    -o StrictHostKeyChecking=no \
    ${DPU_USER}@${DPU_HOST} \
    "cd ${DPU_BASE_DIR}/build && ./react.sh -c ${CORES} -o 70 ${DPU_ARGS[@]}" &

  sleep 6

  # Start tcpdump captures
  sudo -A timeout 65 tcpdump -i ens5f0np0 -n -vvv udp src port 53 and src host 192.168.5.11 -w "responses_after_${CORES}.pcap" &
  sudo -A timeout 65 tcpdump -i ens5f1np1 -n -vvv udp src port 53 and src host 192.168.5.11 -w "responses_before_${CORES}.pcap" &

  # Trim a random packet window
  xstart=$(shuf -i 0-850000 -n 1)
  xend=$((xstart + 60000))
  sudo -A editcap -r dns1M.pcap trimmed.pcap $xstart-$xend

  # Replay traffic
  sudo -A tcpreplay -i ens5f0np0 --pps=1000 trimmed.pcap 2>&1 &

  # Wait for tcpdump and replay to complete
  sleep 70

  # Count packets in responses
  x=$(tcpdump -nn -r "responses_before_${CORES}.pcap" 2>/dev/null | wc -l)
  y=$(tcpdump -nn -r "responses_after_${CORES}.pcap" 2>/dev/null | wc -l)

  if [[ $x -eq 0 ]]; then
    result="Number of cores: ${CORES}, Loss Ratio: NaN"
    echo "$result" >> "$OUTPUT_FILE"
    echo -e "\e[32m${result}\e[0m"
    break
  fi

  ratio=$(awk "BEGIN { printf \"%.2f\", ($x - $y) / $x }")
  result="Number of cores: ${CORES}, Loss Ratio: ${ratio}"

  echo "$result" >> "$OUTPUT_FILE"
  echo -e "\e[32m${result}\e[0m"

  if [[ "$ratio" == "0.00" ]]; then
    break
  fi

done

echo -e "\a"
