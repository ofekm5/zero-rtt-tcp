# Server App

iperf (v2) server for the 0-RTT demo. Listens for connections arriving through the ServerNIC → ClientNIC middleware chain.

The server is **completely unmodified** from the network's perspective — it speaks standard TCP with no awareness of the 0-RTT optimization.

## Usage

```bash
# Start with defaults (port 8080)
iperf -s -p 8080

# Or use the wrapper script
./iperf_server.sh 8080
```

## Node Script

Use `experiments/nodes/server.sh` to start the iperf server on the Server VM via SSM — it handles cleanup, git pull, and foreground launch.
