# Integration Test Report — 2026-05-30

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh`
**Node scripts**: `experiments/zero-rtt-dpdk/nodes/`
**Overall result**: ALL PASSED ✅

## Client Output

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.49:8080

  Connection 1: 1.74 ms

Results:
  Success: 1/1 (100%)
  TTFB Statistics:
    Min:     1.74 ms
    Max:     1.74 ms
    Average: 1.74 ms
    Median:  1.74 ms
```

## ClientNIC Log (0-RTT activity)

```
[1;33m[18:49:38] Killing any leftover clientnic-dpdk-forwarder/tcpdump processes...[0m
[1;33m[18:49:39] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:49:39] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[18:49:39] Using existing binary: /home/ec2-user/zero-rtt-demo/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder[0m
[1;33m[18:49:39] Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): 02:77:5c:47:e0:ed[0m
[1;33m[18:49:39] IP forwarding: enabled[0m
[1;33m[18:49:39] Starting tcpdump on eth0 ? /tmp/client_side.pcap ...[0m
[1;33m[18:49:40] Starting clientnic-dpdk-forwarder ? transparent forwarding with V-stamp. Press Ctrl+C to stop.[0m
[1;33m[18:49:40]   --port=8080 --gw-mac=02:77:5c:47:e0:ed[0m

EAL: Detected CPU lcores: 2
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'PA'
EAL: VFIO support initialized
EAL: Using IOMMU type 8 (No-IOMMU)
EAL: Probe PCI driver: net_ena (1d0f:ec20) device: 0000:00:06.0 (socket -1)
ena_get_metrics_entries(): 0x6 customer metrics are supported
TELEMETRY: No legacy callbacks, legacy socket not created
FORWARDER: ClientNIC DPDK Forwarder starting (port=8080, client=eth0, server=eth1)
FORWARDER: Gateway MAC: 02:77:5c:47:e0:ed
FORWARDER: eth0: initialized on eth0 (ifindex=2, MAC=02:e4:e8:be:be:bd)
FORWARDER: eth1: DPDK port 0 started (MAC=02:8e:22:ca:e7:5f)
FORWARDER: Entering busy-poll loop...
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb6bdd0e8 in ack-num
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:49:24] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[18:49:24] Using existing binary: /home/ec2-user/zero-rtt-demo/servernic/dpdk/builddir/servernic-dpdk[0m
[1;33m[18:49:24] ClientNIC-side gateway MAC (eth1): 02:8e:22:ca:e7:5f[0m
[1;33m[18:49:24] Server-side gateway MAC (eth2):    02:79:c9:50:e3:0d[0m
[1;33m[18:49:24] IP forwarding: enabled[0m
[1;33m[18:49:24] Starting servernic-dpdk ? watching for flows. Press Ctrl+C to stop.[0m
[1;33m[18:49:24]   --port=8080 --gw-mac=02:8e:22:ca:e7:5f --server-gw-mac=02:79:c9:50:e3:0d[0m

EAL: Detected CPU lcores: 2
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'PA'
EAL: VFIO support initialized
EAL: Using IOMMU type 8 (No-IOMMU)
EAL: Probe PCI driver: net_ena (1d0f:ec20) device: 0000:00:06.0 (socket -1)
ena_get_metrics_entries(): 0x6 customer metrics are supported
TELEMETRY: No legacy callbacks, legacy socket not created
SERVERNIC: ServerNIC DPDK starting (port=8080, client-iface=eth1, server-iface=eth2)
SERVERNIC: eth1: DPDK port 0 started (MAC=02:77:5c:47:e0:ed)
SERVERNIC: eth2: initialized on eth2 (ifindex=4, MAC=02:6c:d8:0e:d4:a7)
SERVERNIC: Entering busy-poll loop...
SERVERNIC: SYN: new flow, V=0xb6bdd0e8
SERVERNIC: SYN-ACK: delta=0x90771689, V=0xb6bdd0e8, real_isn=0x2646ba5f
SERVERNIC: SYN-ACK: flushed 2 buffered c2s packets
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```
[1;33m[18:49:14] Killing any leftover server.py...[0m
[1;33m[18:49:15] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:49:16] Server VM IP: 10.1.2.49[0m
[1;33m[18:49:16] Will listen on 0.0.0.0:8080[0m

[1;33m[18:49:16] Starting server.py ? press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
[10.1.0.188:57664] Received 22 bytes
[10.1.0.188:57664] Sent 40 bytes
```

## Packet Analysis

```
T8 mode: loading /tmp/client_side.pcap  (eth0 - client side)
  eth0: 11 packet(s)

  eth0 SYNs: 1
  eth0 SYN-ACKs: 1
    t=1780166991.489651  ISN=3065893096  10.1.2.49:8080 -> 10.1.0.188:57664

-- A. Spoofed SYN-ACK on eth0 (T8 mode) ---------------------------------
[PASS] At least one SYN-ACK seen on eth0  (1 SYN-ACK(s))

-- B. No duplicate SYN-ACK per flow (real SYN-ACK dropped at ServerNIC) --
[PASS] Exactly one SYN-ACK per flow on eth0  (1 flow(s) OK)

-- C. 0-RTT Timing (informational) --------------------------------------
  flow dport=57664: SYN_t=1780166991.489613  SYN-ACK_t=1780166991.489651  OK
[PASS] SYN-ACK follows SYN in capture (informational)  (1/1 flows)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 11 packets valid)

------------------------------------------------------------
All checks passed.
```
