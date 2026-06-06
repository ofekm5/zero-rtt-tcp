# Client App

iperf (v2) client for the 0-RTT demo. Connects to the server through the ClientNIC → ServerNIC middleware chain.

The client is **completely unmodified** from the network's perspective — it sends standard TCP flows with no awareness of the 0-RTT optimization happening in the network layer.

## Usage

```bash
# Single 1 MB flow
iperf -c <server-ip> -p 8080 -n 1M -f m

# Run the full stress test suite (multi-flow, parallel, burst, UDP flood)
./iperf_client.sh <server-ip> 8080
```

## Interactive Mode

Use `experiments/nodes/client.sh` for interactive testing — press Enter to send a new flow each time.

## Stress Suite

`iperf_client.sh` runs the full suite: sequential flows, parallel streams, bulk transfers, short-lived burst connections, bidirectional tests, and UDP flood.
