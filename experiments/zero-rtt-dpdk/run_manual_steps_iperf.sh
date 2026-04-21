#!/usr/bin/env bash
# Manual experiment (iperf variant) — open 4 terminals, one per VM.
# Identical startup order to run_manual_steps.sh but uses iperf instead of
# client.py / server.py, enabling multi-flow, parallel, burst and stress tests.
#
# Startup order: Terminal 1 → 2 → 3 → 4 (wait for each before starting the next).
# Stack deploy: 2026-04-16

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 1 — SERVER  (i-02a8f186bb1474a99)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-02a8f186bb1474a99 --region eu-central-1

# On the Server VM:
bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/server_iperf.sh
# Wait until you see: "Server listening on port 5001"  → then start Terminal 2

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 2 — SERVERNIC  (i-041ca50d93d12aabf)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-041ca50d93d12aabf --region eu-central-1

bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/servernic.sh
# Wait until you see: "Sniffing on [eth0, eth1]"  → then start Terminal 3

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 3 — CLIENTNIC  (i-0321f5def26bd43b6)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-0321f5def26bd43b6 --region eu-central-1

SKIP_BUILD=1 bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/clientnic.sh 02:f9:c7:e0:e8:71
# Wait until you see: "Entering busy-poll loop..."  → then start Terminal 4
# On each new connection you'll see:
#   SYN: flow created, spoofed SYN-ACK sent, SYN forwarded
#   SYN-ACK: delta=<N>, flushed <M> buffered pkts

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 4 — CLIENT  (i-09c7b765bf1470a45)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-09c7b765bf1470a45 --region eu-central-1

# On the Client VM:
bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/client_iperf.sh 10.1.2.28
# Full stress suite runs automatically — results land in /tmp/iperf_results/
# Watch Terminal 3 for per-flow SYN/delta logs while the suite runs.

# ══════════════════════════════════════════════════════════════════════════════
# AFTER THE RUN — validate pcap (run on Terminal 3 after Ctrl+C)
# ══════════════════════════════════════════════════════════════════════════════
cp /home/ec2-user/zero-rtt-demo/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py && python3 /tmp/validate_0rtt.py --client-pcap /tmp/client_side.pcap --server-pcap /tmp/server_side.pcap
