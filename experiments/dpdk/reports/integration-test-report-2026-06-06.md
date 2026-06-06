# Integration Test Report — 2026-06-06

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 4 FAILURE(S) ❌

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
```

## Client Output

```
=== Repeated Connection Test (5 connections) ===
Server: 10.1.2.134:8080


Results:
  Success: 0/5 (0%)
```

## ClientNIC Log (0-RTT activity)

```
bash: /home/ec2-user/zero-rtt-demo/experiments/dpdk/clientnic.sh: No such file or directory
```

## ServerNIC Log

```
bash: /home/ec2-user/zero-rtt-demo/experiments/dpdk/servernic.sh: No such file or directory
```

## Server Log

```
bash: /home/ec2-user/zero-rtt-demo/experiments/nodes/server.sh: No such file or directory
```

## Packet Analysis

```
T8 mode: loading /tmp/client_side.pcap  (eth0 - client side)
[FAIL] Cannot read /tmp/client_side.pcap: [Errno 2] No such file or directory: '/tmp/client_side.pcap'
```
