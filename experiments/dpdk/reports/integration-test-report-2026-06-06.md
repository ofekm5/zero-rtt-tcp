# Integration Test Report — 2026-06-06

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: ALL PASSED ✅

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): n=5  min=0.990  mean=2.066  median=1.407  max=3.653 ms
  servernic TTFB (in-app): n=5  min=0.656  mean=1.491  median=0.743  max=2.854 ms
  Client TTFB   : n=5  min=1.503  mean=2.882  median=1.833  max=5.221 ms
  Client FCT    : n=5  min=1.533  mean=3.042  median=1.887  max=5.782 ms
```

## Client Output

```
=== Repeated Connection Test (5 connections) ===
Server: 10.1.2.134:8080

[METRIC] ttfb node=client flow=10.1.2.134:8080 ms=4.099
[METRIC] fct node=client flow=10.1.2.134:8080 ms=4.139
  Connection 1: 4.10 ms
[METRIC] ttfb node=client flow=10.1.2.134:8080 ms=5.221
[METRIC] fct node=client flow=10.1.2.134:8080 ms=5.782
  Connection 2: 5.22 ms
[METRIC] ttfb node=client flow=10.1.2.134:8080 ms=1.753
[METRIC] fct node=client flow=10.1.2.134:8080 ms=1.887
  Connection 3: 1.75 ms
[METRIC] ttfb node=client flow=10.1.2.134:8080 ms=1.503
[METRIC] fct node=client flow=10.1.2.134:8080 ms=1.533
  Connection 4: 1.50 ms
[METRIC] ttfb node=client flow=10.1.2.134:8080 ms=1.833
[METRIC] fct node=client flow=10.1.2.134:8080 ms=1.867
  Connection 5: 1.83 ms

Results:
  Success: 5/5 (100%)
  TTFB Statistics:
    Min:     1.50 ms
    Max:     5.22 ms
    Average: 2.88 ms
    Median:  1.83 ms
    Std Dev: 1.68 ms
  FCT Statistics:
    Min:     1.53 ms
    Max:     5.78 ms
    Average: 3.04 ms
    Median:  1.89 ms
    Std Dev: 1.85 ms
```

## ClientNIC Log (0-RTT activity)

```
[1;33m[17:37:48] Killing any leftover clientnic-dpdk-forwarder/tcpdump processes...[0m
[1;33m[17:37:49] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[17:37:50] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[17:37:50] Using existing binary: /home/ec2-user/zero-rtt-demo/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder[0m
[1;33m[17:37:50] Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): 02:dd:fb:6e:7e:41[0m
[1;33m[17:37:50] IP forwarding: enabled[0m
[1;33m[17:37:50] Starting tcpdump on eth0 ? /tmp/client_side.pcap ...[0m
[1;33m[17:37:51] Starting clientnic-dpdk-forwarder ? transparent forwarding with V-stamp. Press Ctrl+C to stop.[0m
[1;33m[17:37:51]   --port=8080 --gw-mac=02:dd:fb:6e:7e:41[0m

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
FORWARDER: Gateway MAC: 02:dd:fb:6e:7e:41
FORWARDER: eth0: initialized on eth0 (ifindex=2, MAC=02:84:3f:75:79:13)
FORWARDER: eth1: DPDK port 0 started (MAC=02:01:27:1a:67:09)
FORWARDER: Entering busy-poll loop...
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5ba4cfbb in ack-num
FORWARDER: [METRIC] ttfb node=clientnic flow=10.1.0.26:36078->10.1.2.134:8080 us=3653.4
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1c1757b0 in ack-num
FORWARDER: [METRIC] ttfb node=clientnic flow=10.1.0.26:36086->10.1.2.134:8080 us=2943.1
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x629059f4 in ack-num
FORWARDER: [METRIC] ttfb node=clientnic flow=10.1.0.26:36088->10.1.2.134:8080 us=1407.0
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe518b061 in ack-num
FORWARDER: [METRIC] ttfb node=clientnic flow=10.1.0.26:36094->10.1.2.134:8080 us=989.7
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0346f3d8 in ack-num
FORWARDER: [METRIC] ttfb node=clientnic flow=10.1.0.26:36098->10.1.2.134:8080 us=1338.3
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
EAL: Selected IOVA mode 'PA'
EAL: VFIO support initialized
EAL: Using IOMMU type 8 (No-IOMMU)
EAL: Probe PCI driver: net_ena (1d0f:ec20) device: 0000:00:06.0 (socket -1)
ena_get_metrics_entries(): 0x6 customer metrics are supported
TELEMETRY: No legacy callbacks, legacy socket not created
SERVERNIC: ServerNIC DPDK starting (port=8080, client-iface=eth1, server-iface=eth1)
SERVERNIC: eth1: DPDK port 0 started (MAC=02:dd:fb:6e:7e:41)
SERVERNIC: eth2: initialized on eth1 (ifindex=5, MAC=02:00:3a:b7:5d:29)
SERVERNIC: Entering busy-poll loop...
SERVERNIC: SYN: new flow, V=0x5ba4cfbb
SERVERNIC: SYN-ACK: delta=0x1aa2a777, V=0x5ba4cfbb, real_isn=0x41022844
SERVERNIC: SYN-ACK: flushed 2 buffered c2s packets
SERVERNIC: [METRIC] ttfb node=servernic flow=10.1.0.26:36078->10.1.2.134:8080 us=2854.4
SERVERNIC: SYN: new flow, V=0x1c1757b0
SERVERNIC: SYN-ACK: delta=0x9e3433d6, V=0x1c1757b0, real_isn=0x7de323da
SERVERNIC: SYN-ACK: flushed 2 buffered c2s packets
SERVERNIC: [METRIC] ttfb node=servernic flow=10.1.0.26:36086->10.1.2.134:8080 us=2477.2
SERVERNIC: SYN: new flow, V=0x629059f4
SERVERNIC: SYN-ACK: delta=0x898d7fb0, V=0x629059f4, real_isn=0xd902da44
SERVERNIC: [METRIC] ttfb node=servernic flow=10.1.0.26:36088->10.1.2.134:8080 us=726.2
SERVERNIC: SYN: new flow, V=0xe518b061
SERVERNIC: SYN-ACK: delta=0x1fd40b3c, V=0xe518b061, real_isn=0xc544a525
SERVERNIC: [METRIC] ttfb node=servernic flow=10.1.0.26:36094->10.1.2.134:8080 us=743.1
SERVERNIC: SYN: new flow, V=0x0346f3d8
SERVERNIC: SYN-ACK: delta=0x445f20da, V=0x0346f3d8, real_isn=0xbee7d2fe
SERVERNIC: [METRIC] ttfb node=servernic flow=10.1.0.26:36098->10.1.2.134:8080 us=655.7
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```
[1;33m[17:37:28] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[17:37:28] Server VM IP: 10.1.2.134[0m
[1;33m[17:37:28] Will listen on 0.0.0.0:8080[0m

[1;33m[17:37:28] Starting server.py ? press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
[10.1.0.26:36078] Received 22 bytes
[10.1.0.26:36078] Sent 40 bytes
[10.1.0.26:36086] Received 22 bytes
[10.1.0.26:36086] Sent 40 bytes
[10.1.0.26:36088] Received 22 bytes
[10.1.0.26:36088] Sent 40 bytes
[10.1.0.26:36094] Received 22 bytes
[10.1.0.26:36094] Sent 40 bytes
[10.1.0.26:36098] Received 22 bytes
[10.1.0.26:36098] Sent 40 bytes
```

## Packet Analysis

```
T8 mode: loading /tmp/client_side.pcap  (eth0 - client side)
  eth0: 50 packet(s)

  eth0 SYNs: 5
  eth0 SYN-ACKs: 5
    t=1780767480.970172  ISN=1537527739  10.1.2.134:8080 -> 10.1.0.26:36078
    t=1780767480.974433  ISN=471291824  10.1.2.134:8080 -> 10.1.0.26:36086
    t=1780767480.980277  ISN=1653627380  10.1.2.134:8080 -> 10.1.0.26:36088
    t=1780767480.982259  ISN=3843600481  10.1.2.134:8080 -> 10.1.0.26:36094
    t=1780767480.983977  ISN=54981592  10.1.2.134:8080 -> 10.1.0.26:36098

-- A. Spoofed SYN-ACK on eth0 (T8 mode) ---------------------------------
[PASS] At least one SYN-ACK seen on eth0  (5 SYN-ACK(s))

-- B. No duplicate SYN-ACK per flow (real SYN-ACK dropped at ServerNIC) --
[PASS] Exactly one SYN-ACK per flow on eth0  (5 flow(s) OK)

-- C. 0-RTT Timing (informational) --------------------------------------
  flow dport=36078: SYN_t=1780767480.970140  SYN-ACK_t=1780767480.970172  OK
  flow dport=36086: SYN_t=1780767480.974419  SYN-ACK_t=1780767480.974433  OK
  flow dport=36088: SYN_t=1780767480.980270  SYN-ACK_t=1780767480.980277  OK
  flow dport=36094: SYN_t=1780767480.982245  SYN-ACK_t=1780767480.982259  OK
  flow dport=36098: SYN_t=1780767480.983963  SYN-ACK_t=1780767480.983977  OK
[PASS] SYN-ACK follows SYN in capture (informational)  (5/5 flows)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 50 packets valid)

------------------------------------------------------------
All checks passed.
```
