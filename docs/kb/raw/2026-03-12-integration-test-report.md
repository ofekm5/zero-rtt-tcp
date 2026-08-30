---
type: Raw Source
title: "Integration Test Report — 2026-03-12"
description: "Region: eu-central-1. All 4 VMs running. Code pulled from main before the run."
tags: [experiments, integration-test, archive]
timestamp: 2026-06-06T15:24:48+03:00
---

# Integration Test Report — 2026-03-12

## Environment

| VM | Instance ID | Private IP |
|----|-------------|------------|
| smartnics-server | i-0a76a862204583b06 | 10.1.2.195 |
| smartnics-servernic | i-0563cf3279539fe9c | — |
| smartnics-clientnic | i-015f702db89f54213 | — |
| smartnics-client | i-0c1bd7d086d44920d | 10.1.0.190 |

Region: eu-central-1. All 4 VMs running. Code pulled from `main` before the run.

---

## Summary

Single run — **ALL CHECKS PASSED** (8/8).

This is the first clean run that validates the full 0-RTT mechanism end-to-end, including the timing check (spoofed SYN-ACK arriving before real). The iptables fix committed at the end of the 2026-03-07 session (blocking kernel FORWARD for port 8080) has been confirmed working.

```
[PASS] Server listening on :8080
[PASS] ServerNIC: IP forwarding enabled
[PASS] ClientNIC: IP forwarding enabled (set persistently by CDK)
[PASS] All 3 client connections succeeded
[PASS] tcpdump stopped
[PASS] Server received data from client
[PASS] ClientNIC: flow table entries seen in log
[PASS] Packet capture analysis: all checks passed
```

---

## Detailed Results

### Check 1 — Server Listening: PASS

`ss -tlnp | grep 8080` returned LISTENING on Server VM.

### Check 2 — Infrastructure Pre-flight: PASS

- ServerNIC: `ip_forward = 1`
- ClientNIC: `ip_forward = 1` (set persistently by CDK user data)

### Check 3 — Basic Connectivity: PASS

```
=== Repeated Connection Test (3 connections) ===
Server: 10.1.2.195:8080

  Connection 1: 409.80 ms
  Connection 2: 351.82 ms
  Connection 3: 359.93 ms

Results:
  Success: 3/3 (100%)
  TTFB Statistics:
    Min:     351.82 ms
    Max:     409.80 ms
    Average: 373.85 ms
    Median:  359.93 ms
    Std Dev: 31.40 ms
```

**Note on TTFB:** The 350–410 ms range is expected and correct. With `iptables FORWARD DROP` on port 8080, the kernel no longer forwards packets at line rate — all application traffic flows exclusively through Scapy (userspace Python). The Python/Scapy processing overhead (~100–200 ms) plus the genuine intra-VPC RTT accounts for this latency. This is the intended behavior: connections now go through the 0-RTT pipeline rather than kernel shortcut.

### Check 4 — Server Received Data: PASS

```
[10.1.0.190:36670] Received 22 bytes
[10.1.0.190:36670] Sent 40 bytes
[10.1.0.190:36672] Received 22 bytes
[10.1.0.190:36672] Sent 40 bytes
[10.1.0.190:36680] Received 22 bytes
[10.1.0.190:36680] Sent 40 bytes
```

All 3 connections delivered data to the server correctly. Sequence number translation was transparent — server saw clean client-port-keyed connections.

### Check 5 — ClientNIC Flow Table: PASS

3 flows created, all with non-zero deltas. Buffered packets flushed for each flow after real SYN-ACK processed:

| Flow (client port) | Delta |
|--------------------|-------|
| 36670 | 3,980,068,009 |
| 36672 | 579,144,604 |
| 36680 | 2,546,296,105 |

Log excerpt (representative):
```
[INFO] clientnic: SYN received, flow created: FlowKey(src_ip='10.1.0.190', src_port=36670, dst_ip='10.1.2.195', dst_port=8080)
[INFO] clientnic: Spoofed SYN-ACK sent to client
[INFO] clientnic: Original SYN forwarded to server
[INFO] clientnic: Real SYN-ACK received, delta=3980068009 for flow: FlowKey(...)
[INFO] clientnic: Flushed 2 buffered packets for flow: FlowKey(...)
```

The `Flushed 2 buffered packets` line confirms the client sent application data before the real SYN-ACK arrived — the core 0-RTT buffering mechanism is operating as designed.

**Benign warning observed:**
```
SyntaxWarning: 'iface' has no effect on L3 I/O send()
```
This is a Scapy informational warning for `send(iface=...)` calls. Routing is handled correctly via OS routes (`ip route replace`), so the `iface=` argument is redundant but harmless.

### Check 6 — Packet Capture Analysis: PASS

33 packets captured on both eth0 and eth1.

#### A. Spoofed SYN-ACK Detection — PASS

| Interface | SYN-ACKs | ISNs |
|-----------|----------|------|
| eth0 (client-facing) | 3 | 3,880,582,940 / 627,031,963 / 1,498,340,757 |
| eth1 (server-facing) | 3 | 4,195,482,227 / 47,887,359 / 3,247,011,948 |

All 3 eth0 SYN-ACKs have ISNs distinct from the eth1 real ISN set → confirmed spoofed. No forwarded-real SYN-ACKs on eth0 (0 of 3) — real SYN-ACKs are correctly dropped by ClientNIC.

#### B. ISN Delta — PASS

| Flow (dport) | Spoofed ISN | Real ISN | Delta |
|-------------|-------------|----------|-------|
| 36670 | 3,880,582,940 | 4,195,482,227 | 3,980,068,009 |
| 36672 | 627,031,963 | 47,887,359 | 579,144,604 |
| 36680 | 1,498,340,757 | 3,247,011,948 | 2,546,296,105 |

Deltas match exactly what was logged by `clientnic.main`. All non-zero. ✓

#### C. 0-RTT Timing — PASS (informational)

Spoofed SYN-ACK arrived **before** the real SYN-ACK on all 3 flows:

| Flow (dport) | Spoofed timestamp | Real timestamp | Lead time |
|-------------|-------------------|----------------|-----------|
| 36670 | 1773325562.413976 | 1773325562.613271 | **+199 ms** |
| 36672 | 1773325562.854744 | 1773325562.938125 | **+83 ms** |
| 36680 | 1773325563.207084 | 1773325563.326187 | **+119 ms** |

**This is the first run where the 0-RTT timing check passes.** The spoofed SYN-ACK reaching the client ~83–199 ms before the real one means the client can complete its local handshake and begin sending application data immediately. The real SYN-ACK, when it eventually arrives, is dropped by ClientNIC.

#### D. Checksum Integrity — PASS

| Interface | Packets checked | Bad checksums |
|-----------|----------------|---------------|
| eth0 (client side) | 33 | 0 |
| eth1 (server side) | 33 | 0 |

All rewritten packets have valid IP and TCP checksums. The `del pkt[IP].chksum / del pkt[TCP].chksum` + Scapy auto-recalculation mechanism is working correctly.

---

## Key Finding: 0-RTT Mechanism Fully Validated

The iptables fix (`FORWARD DROP` for tcp port 8080 on both NIC VMs) has resolved the kernel-race condition identified in the 2026-03-07 report. With kernel forwarding blocked for application traffic:

1. **Spoofed SYN-ACK reaches client first** (83–199 ms lead over real) ✓
2. **Client buffers data and flushes** upon delta resolution ✓
3. **Sequence number translation is applied** on all subsequent packets ✓
4. **Data delivered correctly** to server (zero corruption) ✓
5. **Checksums valid** on all 66 captured packets (33 + 33) ✓

The 0-RTT TCP demonstration is fully functional.

---

## Overall Result

| Check | Result |
|-------|--------|
| All 4 VMs discovered | PASS |
| Server listening on :8080 | PASS |
| IP forwarding enabled (ServerNIC) | PASS |
| IP forwarding enabled (ClientNIC) | PASS |
| Basic connectivity (3/3 connections) | PASS |
| Server received data | PASS |
| ClientNIC flow table state (delta, spoof, flush) | PASS |
| Spoofed SYN-ACK detection (distinct ISN on eth0) | PASS |
| Real SYN-ACK dropped (not forwarded to client) | PASS |
| ISN deltas non-zero and consistent | PASS |
| 0-RTT timing (spoofed before real) | **PASS** ← first passing run |
| Checksum integrity (eth0 + eth1) | PASS |
