# Integration Test Report — 2026-03-18

## Environment

| VM | Instance ID | Private IP |
|----|-------------|------------|
| smartnics-server | i-0e3ad61230423a9fd | 10.1.2.183 |
| smartnics-servernic | i-0f9eebbcf7eea890e | 10.1.1.44 |
| smartnics-clientnic | i-058dc19fde0eeb012 | — |
| smartnics-client | i-0c1ab99a587a02fac | 10.1.0.61 |

Region: eu-central-1. All 4 VMs running. Code pulled from `main` before the run.

---

## Summary

Two runs performed — **ALL CHECKS PASSED (8/8)** on both.

### Bug fixed this session

**ServerNIC interface mismatch** — after the `refactor(servernic): restructure to SmartNIC pipeline layout` commit, the servernic code defaulted to `eth1`/`eth2` but the VM only has `eth0` (10.1.1.44, middle subnet) and `eth1` (10.1.2.36, server subnet). The app crashed immediately on startup with `ValueError: Interface 'eth2' not found !`, so no SYN-ACKs ever returned to ClientNIC.

**Fix:** `run_experiment.sh` now passes `--client-iface eth0 --server-iface eth1` when starting ServerNIC.

Also fixed: `run_experiment.sh` had Windows line endings (CRLF) which prevented execution in WSL (`/usr/bin/env: 'bash\r': No such file or directory`). Converted to LF and added `.gitattributes` to enforce LF for `*.sh` and `*.py` going forward.

---

## Detailed Results (second run — 11:50 UTC)

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

### Check 1 — Server Listening: PASS

`ss -tlnp | grep 8080` returned LISTENING on Server VM.

### Check 2 — Infrastructure Pre-flight: PASS

- ServerNIC: `ip_forward = 1`
- ClientNIC: `ip_forward = 1` (set persistently by CDK user data)

### Check 3 — Basic Connectivity: PASS

```
=== Repeated Connection Test (3 connections) ===
Server: 10.1.2.183:8080

  Connection 1: 389.06 ms
  Connection 2: 423.75 ms
  Connection 3: 395.94 ms

Results:
  Success: 3/3 (100%)
  TTFB Statistics:
    Min:     389.06 ms
    Max:     423.75 ms
    Average: 402.92 ms
    Median:  395.94 ms
    Std Dev: 18.37 ms
```

### Check 4 — Server Received Data: PASS

```
[10.1.0.61:58304] Received 22 bytes
[10.1.0.61:58304] Sent 40 bytes
[10.1.0.61:58308] Received 22 bytes
[10.1.0.61:58308] Sent 40 bytes
[10.1.0.61:58314] Received 22 bytes
[10.1.0.61:58314] Sent 40 bytes
```

### Check 5 — ClientNIC Flow Table: PASS

3 flows created, all with non-zero deltas. Flows 1 and 3 flushed 2 buffered packets each (client sent data before real SYN-ACK arrived — core 0-RTT buffering operating correctly).

| Flow (client port) | Delta | Buffered pkts flushed |
|--------------------|-------|-----------------------|
| 58304 | 3,075,871,609 | 2 |
| 58308 | 1,623,198,199 | 0 |
| 58314 | 830,610,479 | 2 |

Log excerpt:
```
[INFO] clientnic: SYN: flow created + spoofed SYN-ACK sent [FlowKey(src_ip='10.1.0.61', src_port=58304, dst_ip='10.1.2.183', dst_port=8080)]
[INFO] clientnic: SYN-ACK: delta=3075871609, flushed 2 pkts [FlowKey(...)]
[INFO] clientnic: SYN: flow created + spoofed SYN-ACK sent [FlowKey(src_ip='10.1.0.61', src_port=58308, ...)]
[INFO] clientnic: SYN-ACK: delta=1623198199, flushed 0 pkts [FlowKey(...)]
[INFO] clientnic: SYN: flow created + spoofed SYN-ACK sent [FlowKey(src_ip='10.1.0.61', src_port=58314, ...)]
[INFO] clientnic: SYN-ACK: delta=830610479, flushed 2 pkts [FlowKey(...)]
```

**Benign warning:**
```
SyntaxWarning: 'iface' has no effect on L3 I/O send()
```
Harmless — routing handled via OS routes; `iface=` argument is redundant but does not affect correctness.

### Check 6 — Packet Capture Analysis: PASS

33 packets captured on both eth0 and eth1.

#### A. Spoofed SYN-ACK Detection — PASS

| Interface | SYN-ACKs | ISNs |
|-----------|----------|------|
| eth0 (client-facing) | 3 | 1,016,412,420 / 4,001,259,925 / 3,359,907,777 |
| eth1 (server-facing) | 3 | 2,235,508,107 / 2,378,061,726 / 2,529,297,298 |

All 3 eth0 SYN-ACKs have ISNs distinct from the real ISN set. No forwarded-real SYN-ACKs on eth0 (0 of 3) — real SYN-ACKs correctly dropped by ClientNIC.

#### B. ISN Delta — PASS

| Flow (dport) | Spoofed ISN | Real ISN | Delta |
|-------------|-------------|----------|-------|
| 58304 | 1,016,412,420 | 2,235,508,107 | 3,075,871,609 |
| 58308 | 4,001,259,925 | 2,378,061,726 | 1,623,198,199 |
| 58314 | 3,359,907,777 | 2,529,297,298 | 830,610,479 |

Deltas match exactly what was logged by `clientnic.main`. All non-zero. ✓

#### C. 0-RTT Timing — PASS (informational)

Spoofed SYN-ACK arrived before the real SYN-ACK on all 3 flows:

| Flow (dport) | Spoofed timestamp | Real timestamp | Lead time |
|-------------|-------------------|----------------|-----------|
| 58304 | 1773827465.729779 | 1773827465.906829 | **+177 ms** |
| 58308 | 1773827466.229558 | 1773827466.311786 | **+82 ms** |
| 58314 | 1773827466.653616 | 1773827466.767764 | **+114 ms** |

#### D. Checksum Integrity — PASS

| Interface | Packets checked | Bad checksums |
|-----------|----------------|---------------|
| eth0 (client side) | 33 | 0 |
| eth1 (server side) | 33 | 0 |

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
| 0-RTT timing (spoofed before real) | PASS |
| Checksum integrity (eth0 + eth1) | PASS |
