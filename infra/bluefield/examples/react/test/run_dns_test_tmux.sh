#!/bin/bash

# === Script Name ===
# run_dns_test_tmux.sh
#
# === Description ===
# This script automates the setup and execution of a multi-pane DNS test environment using `tmux`.
# It runs a full pipeline for evaluating the DOCA Flow `react.sh` program on a remote DPU,
# capturing DNS traffic before and after processing, and replaying crafted traffic for analysis.
#
# It includes:
# - Password-prompting for local sudo and DPU SSH access (askpass-based, cleaned up on exit)
# - Optional debug mode (`--debug`) that shows local and remote counters via extra panes
# - Automated packet trimming from a 1M-DNS-request PCAP (`dns1M.pcap`)
# - Traffic replay of trimmed requests and attack traffic
# - Automatic PCAP comparison between input/output traffic using `compare_pcaps.py`
#
# === Usage ===
# ./run_dns_test_tmux.sh [--debug] [react.sh args...]
#
# - `--debug`: Enable debug mode with additional panes for monitoring counters
# - Other arguments are passed directly to the remote `react.sh` script
#
# === Requirements ===
# - tmux must be installed
# - Local sudo access (used for tcpdump, editcap, tcpreplay)
# - SSH access to the DPU (password-based)
# - Pre-existing files: `dns1M.pcap`, `attack.pcap`, `compare_pcaps.py`
#
# === Output ===
# - `responses_before.pcap` and `responses_after.pcap` (captured traffic)
# - Live console output across tmux panes, including the comparison results
#
# === Notes ===
# - `tmux attach` is triggered automatically at the end
# - Layout adjusts dynamically based on debug mode
# - Pane order and flow are designed to match logical experiment stages


SESSION=dns_test
DPU_USER=ubuntu
DPU_HOST=192.168.27.3
DPU_BASE_DIR=/home/ubuntu/sources/dh2156/samples/doca_flow/react
DEBUG=false
DPU_ARGS=()

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--debug" ]]; then
    DEBUG=true
  else
    DPU_ARGS+=("$arg")
  fi
done

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

# Start tmux session
tmux new-session -d -s $SESSION

if [ "$DEBUG" = true ]; then
  # Pane 0: Local counter reading
  tmux send-keys -t $SESSION "bash /u/dh2156/read_counters.sh" C-m

  # Pane 1: Remote OVS counter reading
  tmux split-window -h -t $SESSION
  tmux send-keys -t $SESSION "DISPLAY=:0 SSH_ASKPASS=$DPU_ASKPASS setsid ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no  ${DPU_USER}@${DPU_HOST} 'bash ${DPU_BASE_DIR}/read_ovs_counters.sh'" C-m
fi

# Pane 2: react.sh on DPU, passing filtered arguments
if [ "$DEBUG" = true ]; then
  tmux split-window -v -t $SESSION:0.0
fi

tmux send-keys -t $SESSION \
  "DISPLAY=:0 SSH_ASKPASS=$DPU_ASKPASS setsid ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no ${DPU_USER}@${DPU_HOST} 'cd ${DPU_BASE_DIR}/build && ./react.sh ${DPU_ARGS[*]}'" C-m


sleep 5

# Pane 3: tcpdump for responses_after.pcap
if [ "$DEBUG" = true ]; then
  tmux split-window -v -t $SESSION:0.1
else
   tmux split-window -v -t $SESSION
fi

tmux send-keys -t $SESSION \
  "sudo -A tcpdump -i ens5f0np0 -n -vvv udp src port 53 -w responses_after.pcap" C-m

# Pane 4: tcpdump for responses_before.pcap
if [ "$DEBUG" = true ]; then
  tmux split-window -v -t $SESSION:0.2
else
   tmux split-window -v -t $SESSION:0.0
fi

tmux send-keys -t $SESSION \
  "sudo -A tcpdump -i ens5f1np1 -n -vvv udp src port 53 and src host 192.168.5.11 -w responses_before.pcap" C-m

tmux select-layout -t $SESSION tiled

# Generate random packet window
x=$(shuf -i 0-850000 -n 1)
y=$((x + 60000))
sudo -A editcap -r dns1M.pcap trimmed.pcap $x-$y

# Pane 5: replay trimmed.pcap
if [ "$DEBUG" = true ]; then
  tmux split-window -v -t $SESSION:0.3
else
   tmux split-window -v -t $SESSION:0.1
fi

tmux send-keys -t $SESSION \
  "sudo -A tcpreplay -i ens5f0np0 --pps=1000 trimmed.pcap 2>&1" C-m

# Pane 6: replay attack.pcap
if [ "$DEBUG" = true ]; then
  tmux split-window -v -t $SESSION:0.4
else
   tmux split-window -v -t $SESSION:0.2
fi

tmux send-keys -t $SESSION \
  "sudo -A tcpreplay -i ens5f1np1 --loop=0 --pps=10000 attack.pcap 2>&1" C-m

# Pane 7: comparison after key press
if [ "$DEBUG" = true ]; then
  tmux split-window -h -t $SESSION:0.5
else
   tmux split-window -h -t $SESSION:0.3
fi

tmux send-keys -t $SESSION \
  "echo 'Press any key to compare results...'; read; python3 compare_pcaps.py responses_before.pcap responses_after.pcap" C-m

tmux select-layout -t $SESSION tiled
# Determine final pane index based on DEBUG state
if [ "$DEBUG" = true ]; then
  TARGET_PANE=0.5
else
  TARGET_PANE=0.3
fi

tmux select-pane -t $SESSION:$TARGET_PANE
 tmux attach-session -t $SESSION

# Clean up askpass scripts
trap "rm -f $SUDO_ASKPASS $DPU_ASKPASS" EXIT
