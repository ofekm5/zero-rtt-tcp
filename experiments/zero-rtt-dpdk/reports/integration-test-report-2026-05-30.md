# Integration Test Report — 2026-05-30

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh`
**Node scripts**: `experiments/zero-rtt-dpdk/nodes/`
**Overall result**: 3 FAILURE(S) ❌

## Client Output

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.49:8080


Results:
  Success: 0/1 (0%)
```

## ClientNIC Log (0-RTT activity)

```

```

## ServerNIC Log

```
[1;33m[18:20:22] Killing any leftover servernic processes...[0m
[1;33m[18:20:23] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:20:23] SKIP_BUILD=1 � skipping meson+ninja build.[0m
[1;33m[18:20:23] Using existing binary: /home/ec2-user/zero-rtt-demo/servernic/dpdk/builddir/servernic-dpdk[0m
[1;33m[18:20:23] Discovering ClientNIC eth1 MAC via EC2 API...[0m
[0;31mERROR: Could not determine ClientNIC gateway MAC.[0m
```

## Server Log

```
[1;33m[18:20:14] Killing any leftover server.py...[0m
[1;33m[18:20:15] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:20:16] Server VM IP: 10.1.2.49[0m
[1;33m[18:20:16] Will listen on 0.0.0.0:8080[0m

[1;33m[18:20:16] Starting server.py � press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
```

## Packet Analysis

```
T8 mode: loading /tmp/client_side.pcap  (eth0 - client side)
  eth0: 10 packet(s)

  eth0 SYNs: 1
  eth0 SYN-ACKs: 1
    t=1780165250.971560  ISN=2553584590  10.1.2.49:8080 -> 10.1.0.188:60526

-- A. Spoofed SYN-ACK on eth0 (T8 mode) ---------------------------------
[PASS] At least one SYN-ACK seen on eth0  (1 SYN-ACK(s))

-- B. No duplicate SYN-ACK per flow (real SYN-ACK dropped at ServerNIC) --
[PASS] Exactly one SYN-ACK per flow on eth0  (1 flow(s) OK)

-- C. 0-RTT Timing (informational) --------------------------------------
  flow dport=60526: SYN_t=1780165250.971484  SYN-ACK_t=1780165250.971560  OK
[PASS] SYN-ACK follows SYN in capture (informational)  (1/1 flows)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 10 packets valid)

------------------------------------------------------------
All checks passed.
```

## eBPF TCP Traces

### Client VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 1156673707414, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 0, "dport": 8080, "old_state": "TCP_CLOSE", "new_state": "TCP_SYN_SENT"}
{"ts_ns": 1156674166452, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 60526, "dport": 8080, "old_state": "TCP_SYN_SENT", "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 1161679402981, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 60526, "dport": 8080, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_FIN_WAIT1"}
```

### Server VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 1121356830010, "src": "0.0.0.0", "dst": "0.0.0.0", "sport": 8080, "dport": 0, "old_state": "TCP_CLOSE", "new_state": "TCP_LISTEN"}
```
