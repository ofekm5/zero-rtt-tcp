#!/usr/bin/env bash
# Manual experiment — open 4 terminals, one per VM.
# Startup order: Terminal 1 → 2 → 3 → 4 (wait for each to be ready before starting the next).
# Stack deploy: 2026-04-23

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 1 — SERVER  (i-09a445538fb369485)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-09a445538fb369485 --region eu-central-1
bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/server.sh
# Wait until you see: "Server listening on 0.0.0.0:8080"  → then start Terminal 2

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 2 — SERVERNIC  (i-027f7c04a35c99f4d)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-027f7c04a35c99f4d --region eu-central-1
bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/servernic.sh
# Wait until you see: "Sniffing on [eth0, eth1]"  → then start Terminal 3

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 3 — CLIENTNIC  (i-0eae390cad02f2827)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-0eae390cad02f2827 --region eu-central-1
SKIP_BUILD=1 bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/clientnic.sh 02:26:d3:d5:1c:39
# Wait until you see: "Entering busy-poll loop..."  → then start Terminal 4
# On connection you'll see:
#   SYN: flow created, spoofed SYN-ACK sent, SYN forwarded
#   SYN-ACK: delta=<N>, flushed <M> buffered pkts

# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL 4 — CLIENT  (i-070ecd89440025ab3)
# ══════════════════════════════════════════════════════════════════════════════
aws ssm start-session --target i-070ecd89440025ab3 --region eu-central-1
bash /home/ec2-user/zero-rtt-demo/experiments/zero-rtt-dpdk/nodes/client.sh 10.1.2.119
# Press Enter each time to send a new TCP connection.
# Each press creates a fresh flow — watch Terminal 3 for the delta line.

# ══════════════════════════════════════════════════════════════════════════════
# AFTER THE RUN — validate pcap (run on Terminal 3 after Ctrl+C)
# ══════════════════════════════════════════════════════════════════════════════
cp /home/ec2-user/zero-rtt-demo/clientnic/validate_0rtt_capture.py /tmp/validate_0rtt.py && python3 /tmp/validate_0rtt.py --client-pcap /tmp/client_side.pcap --server-pcap /tmp/server_side.pcap
