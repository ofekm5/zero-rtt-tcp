# Integration Test Report — 2026-03-25

**Implementation**: DPDK (C/DPDK 23.11 ENA PMD)
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh`
**CDK stack**: `infra/dpdk/` — deployed to eu-central-1
**Overall result**: ALL PASSED ✅

## Instance IDs

| VM | Instance ID |
|----|------------|
| Client | i-045135acee074400f |
| ClientNIC | i-09d39f7c8131c4e1c |
| ServerNIC | i-0633388d1d02c2de7 |
| Server | i-0e83c879f81c290f1 |

## Check Results

| Step | Check | Result |
|------|-------|--------|
| 10.1 | `meson setup builddir && ninja` compiles cleanly | ✅ PASS |
| 10.2 | Binary starts, enters busy-poll loop, shuts down cleanly | ✅ PASS |
| 1 | Server listening on :8080 | ✅ PASS |
| 2 | ServerNIC IP forwarding enabled | ✅ PASS |
| 3 | `clientnic-dpdk` process running | ✅ PASS |
| 4 | Client connection succeeded (1/1) | ✅ PASS |
| 6 | Server received data | ✅ PASS |
| 7 | ClientNIC 0-RTT flow table activity | ✅ PASS |
| 8 | Packet capture analysis — all 6 checks passed | ✅ PASS |

## Build Output (Step 10.1)

```
[7/10] Compiling C object clientnic-dpdk.p/packet_processor.c.o
[8/10] Compiling C object clientnic-dpdk.p/translator.c.o
[9/10] Compiling C object clientnic-dpdk.p/capture.c.o
[10/10] Linking target clientnic-dpdk
BUILD_SUCCESS
```

3 pointer-sign warnings in `packet_processor.c` and `translator.c` (DPDK API returns `char *` where `uint8_t *` is expected); no errors.

## Smoke Test Output (Step 10.2)

```
EAL: Probe PCI driver: net_ena (1d0f:ec20) device: 0000:00:06.0 (socket -1)
CLIENTNIC: ClientNIC DPDK starting (port=8080, client=eth0, server=eth1)
CLIENTNIC: Gateway MAC: 02:82:7d:eb:28:65
CLIENTNIC: eth0: initialized on eth0 (ifindex=2, MAC=02:68:f5:0a:e1:c1)
CLIENTNIC: eth1: DPDK port 0 started (MAC=02:5b:6e:63:3f:3f)
CLIENTNIC: capture: writing eth1 packets to /tmp/server_side.pcap
CLIENTNIC: Entering busy-poll loop...
CLIENTNIC: Shutting down...
```

DPDK EAL initialized with IOVA mode PA and no-IOMMU vfio-pci. Both interfaces up. Clean shutdown on SIGTERM.

## Client Output (Step 4)

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.225:8080

  Connection 1: 296.17 ms

Results:
  Success: 1/1 (100%)
  TTFB Statistics:
    Min:     296.17 ms
    Max:     296.17 ms
    Average: 296.17 ms
    Median:  296.17 ms
```

## Server Log (Step 6)

```
Server listening on 0.0.0.0:8080
[10.1.0.34:51918] Received 22 bytes
[10.1.0.34:51918] Sent 40 bytes
```

## ClientNIC DPDK Log (Step 7)

```
CLIENTNIC: ClientNIC DPDK starting (port=8080, client=eth0, server=eth1)
CLIENTNIC: Gateway MAC: 02:82:7d:eb:28:65
CLIENTNIC: eth0: initialized on eth0 (ifindex=2, MAC=02:68:f5:0a:e1:c1)
CLIENTNIC: eth1: DPDK port 0 started (MAC=02:5b:6e:63:3f:3f)
CLIENTNIC: capture: writing eth1 packets to /tmp/server_side.pcap
CLIENTNIC: Entering busy-poll loop...
CLIENTNIC: SYN: flow created, spoofed SYN-ACK sent, SYN forwarded
CLIENTNIC: SYN-ACK: delta=2571737058, flushed 2 buffered pkts
CLIENTNIC: Shutting down...
CLIENTNIC: capture: pcap file closed
```

Key events:
- Spoofed SYN-ACK sent before real handshake completed (0-RTT)
- Real SYN-ACK received from server, `delta=2571737058` (non-zero ✓)
- 2 buffered client packets (ACK + data) flushed and forwarded after delta known
- pcap file closed cleanly on shutdown (no truncation)

## Packet Capture Analysis (Step 10.4)

```
Loading /tmp/client_side.pcap  (eth0 - client side)
Loading /tmp/server_side.pcap  (eth1 - server side)
  eth0: 13 packet(s)
  eth1: 6 packet(s)

  eth0 SYN-ACKs: 1
    t=1774456137.815189  ISN=3907557360  10.1.2.225:8080 -> 10.1.0.34:51918

  eth1 SYN-ACKs: 1
    t=1774456137.933758  ISN=1335820302  10.1.2.225:8080 -> 10.1.0.34:51918

-- A. Spoofed SYN-ACK Detection -----------------------------------------
  Real ISNs seen on eth1: [1335820302]
  Spoofed SYN-ACKs on eth0 (ISN not in real set): 1
  Forwarded-real SYN-ACKs on eth0 (ISN in real set): 0
[PASS] Real SYN-ACK(s) found on eth1  (1 SYN-ACK(s))
[PASS] Spoofed SYN-ACK(s) found on eth0 (distinct ISN)  (1 spoofed, 0 forwarded-real)

-- B. ISN Delta ---------------------------------------------------------
  flow dport=51918: spoofed_ISN=3907557360  real_ISN=1335820302  delta=2571737058
[PASS] All deltas are non-zero  (1 matched flow(s))

-- C. 0-RTT Timing (informational) -------------------------------------
  flow dport=51918: spoofed_t=1774456137.815189  real_t=1774456137.933758  delta=0.119s  OK (spoofed earlier)
[PASS] Spoofed SYN-ACK arrives before real (informational)  (1/1 flows)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 13 packets valid)
[PASS] No bad checksums on eth1 (server side)  (all 6 packets valid)

------------------------------------------------------------
All checks passed.
```

## Key Observations

- **0-RTT confirmed**: spoofed SYN-ACK (ISN=3907557360) arrived at client 119 ms before the real SYN-ACK (ISN=1335820302). Client sent ACK+data immediately.
- **Delta consistent**: `delta=2571737058` matches the value logged by DPDK (`SYN-ACK: delta=2571737058`), confirming the rewriter and validator agree.
- **eth1 capture via DPDK**: `server_side.pcap` written by `capture.c` (`--server-pcap` flag). tcpdump cannot access DPDK-controlled eth1; the built-in pcap writer is the correct approach.
- **Checksums**: all 19 total packets (13 eth0 + 6 eth1) pass checksum validation after seq/ack rewriting and DPDK recalc.

## Failures / Notes

None. All checks passed on first run after deploying the updated CDK stack (with `scapy` added to pip3 install in ClientNIC user data and `capture.c` committed).
