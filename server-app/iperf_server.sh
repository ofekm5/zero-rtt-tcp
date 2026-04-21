#!/bin/bash
# iperf (v2) server for 0-RTT stress testing
# Stays running and accepts multiple sequential clients by default.

PORT=${1:-5001}

echo "=== iperf Server ==="
echo "Listening on port $PORT"
echo "Press Ctrl+C to stop"
echo ""

# -s: server mode (persistent; accepts one client at a time)
# -p: port
iperf -s -p "$PORT"
