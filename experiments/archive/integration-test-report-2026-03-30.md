# Integration Test Report — 2026-03-30

**Implementation**: DPDK
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh` (node-script-driven)
**Node scripts**: `experiments/zero-rtt-dpdk/nodes/`
**Overall result**: ALL PASSED ✅

## Check Results

| Step | Check | Result |
|------|-------|--------|
| 1 | Server listening on :8080 | ✅ PASS |
| 2 | ServerNIC IP forwarding enabled | ✅ PASS |
| 3 | ClientNIC process running (DPDK EAL init, busy-poll loop) | ✅ PASS |
| 4 | Client connections succeeded (1/1) | ✅ PASS |
| 6 | Server received data | ✅ PASS |
| 7 | ClientNIC 0-RTT flow table activity | ✅ PASS |
| A | Spoofed SYN-ACK on eth0 (distinct ISN) | ✅ PASS |
| A | Real SYN-ACK on eth1 | ✅ PASS |
| B | ISN delta non-zero (delta=1739976854) | ✅ PASS |
| C | Spoofed SYN-ACK arrives before real (121ms earlier) | ✅ PASS |
| D | No bad checksums on eth0 (13/13 valid) | ✅ PASS |
| D | No bad checksums on eth1 (12/12 valid) | ✅ PASS |

## Client Output

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.59:8080

  Connection 1: 306.40 ms

Results:
  Success: 1/1 (100%)
  TTFB Statistics:
    Min:     306.40 ms
    Max:     306.40 ms
    Average: 306.40 ms
    Median:  306.40 ms
```

## ClientNIC Log (0-RTT activity)

```
CLIENTNIC: ClientNIC DPDK starting (port=8080, client=eth0, server=eth1)
CLIENTNIC: Gateway MAC: 02:a5:99:4d:9c:e5
CLIENTNIC: eth0: initialized on eth0 (ifindex=2, MAC=02:55:08:be:2a:2d)
CLIENTNIC: eth1: DPDK port 0 started (MAC=02:1d:db:f2:87:43)
CLIENTNIC: capture: writing eth1 packets to /tmp/server_side.pcap
CLIENTNIC: Entering busy-poll loop...
CLIENTNIC: SYN: flow created, spoofed SYN-ACK sent, SYN forwarded
CLIENTNIC: SYN-ACK: delta=1739976854, flushed 2 buffered pkts
```

## Packet Capture Analysis

```
  eth0: 13 packet(s)
  eth1: 12 packet(s)

  eth0 SYN-ACKs: 1  ISN=3544212660  (spoofed)
  eth1 SYN-ACKs: 1  ISN=1804235806  (real)

  flow dport=34704: spoofed_ISN=3544212660  real_ISN=1804235806  delta=1739976854
  flow dport=34704: spoofed_t=...484  real_t=...604  delta=0.121s  (spoofed earlier)

All checks passed.
```

## Failures / Notes

None. Node-script-driven flow validated successfully:
- nodes/server.sh pulled latest code and started server.py
- nodes/servernic.sh set up route, iptables DROP, and started the Scapy forwarder
- nodes/clientnic.sh used SKIP_BUILD=1 + GW_MAC arg, started tcpdump + DPDK binary
- client.py called directly (bypassing client.sh interactive loop)
- server-side pcap must be read after killing the DPDK binary (file is finalized on exit)
