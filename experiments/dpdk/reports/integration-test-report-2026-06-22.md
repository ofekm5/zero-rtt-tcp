# Integration Test Report — 2026-06-22

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 1 FAILURE(S)

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : n=5  min=7346.312  mean=16527.874  median=15463.031  max=33808.578 ms
  Send unlock   : n=5  min=0.390  mean=1.061  median=0.946  max=1.659 ms
  Server gap    : no samples found
```

## Client Output

```
--- Round 1/1: 1 port(s) [8080-8080] x 5 parallel = 5 conns ---
------------------------------------------------------------
Client connecting to 10.1.2.226, TCP port 8080
TCP window size: 0.04 MByte (default)
------------------------------------------------------------
[  4] local 10.1.0.31 port 60178 connected with 10.1.2.226 port 8080
[  3] local 10.1.0.31 port 60170 connected with 10.1.2.226 port 8080
[  5] local 10.1.0.31 port 60192 connected with 10.1.2.226 port 8080
[  6] local 10.1.0.31 port 60206 connected with 10.1.2.226 port 8080
[  7] local 10.1.0.31 port 60214 connected with 10.1.2.226 port 8080
[ ID] Interval       Transfer     Bandwidth
[  7]  0.0- 6.4 sec  1.00 MBytes  1.31 Mbits/sec
[  4]  0.0- 7.3 sec  1.00 MBytes  1.15 Mbits/sec
[  3]  0.0- 8.0 sec  1.00 MBytes  1.05 Mbits/sec
[  5]  0.0-11.5 sec  1.00 MBytes  0.73 Mbits/sec
[  6]  0.0-19.8 sec  1.00 MBytes  0.42 Mbits/sec
[SUM]  0.0-19.8 sec  5.00 MBytes  2.12 Mbits/sec
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
[1;33m[19:45:44] Killing any leftover clientnic-dpdk-forwarder/tcpdump processes...[0m
[1;33m[19:45:45] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[19:45:45] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[19:45:45] Using existing binary: /home/ec2-user/zero-rtt-demo/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder[0m
[1;33m[19:45:45] Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): 02:72:a8:eb:84:81[0m
[1;33m[19:45:45] IP forwarding: enabled[0m
[1;33m[19:45:45] Starting tcpdump on eth0 ? /tmp/client_side.pcap (ports 8080-8080) ...[0m
[1;33m[19:45:46] Starting clientnic-dpdk-forwarder ? transparent forwarding with V-stamp. Press Ctrl+C to stop.[0m
[1;33m[19:45:46]   --port=8080 --port-count=1 --gw-mac=02:72:a8:eb:84:81[0m

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
FORWARDER: ClientNIC DPDK Forwarder starting (port=8080..8080, client=eth0, server=eth1)
FORWARDER: Gateway MAC: 02:72:a8:eb:84:81
FORWARDER: eth0: initialized on eth0 (ifindex=2, MAC=02:69:9c:ea:ca:47)
FORWARDER: eth1: DPDK port 0 started (MAC=02:15:2a:ae:37:9d)
FORWARDER: Entering busy-poll loop...
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x981dedf5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x22ad4804 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf55e9057 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9b2e6ac9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfa624430 in ack-num
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'PA'
EAL: VFIO support initialized
EAL: Using IOMMU type 8 (No-IOMMU)
EAL: Probe PCI driver: net_ena (1d0f:ec20) device: 0000:00:06.0 (socket -1)
ena_get_metrics_entries(): 0x6 customer metrics are supported
TELEMETRY: No legacy callbacks, legacy socket not created
SERVERNIC: ServerNIC DPDK starting (port=8080..8080, client-iface=eth1, server-iface=eth1)
SERVERNIC: eth1: DPDK port 0 started (MAC=02:72:a8:eb:84:81)
SERVERNIC: eth2: initialized on eth1 (ifindex=5, MAC=02:11:5c:64:1c:1b)
SERVERNIC: Entering busy-poll loop...
SERVERNIC: SYN: new flow, V=0x981dedf5
SERVERNIC: SYN: new flow, V=0x22ad4804
SERVERNIC: SYN-ACK: delta=0x9a74601e, V=0x981dedf5, real_isn=0xfda98dd7
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xa1762a9e, V=0x22ad4804, real_isn=0x81371d66
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xf55e9057
SERVERNIC: SYN: new flow, V=0x9b2e6ac9
SERVERNIC: SYN-ACK: delta=0x05356d97, V=0xf55e9057, real_isn=0xf02922c0
SERVERNIC: SYN-ACK: delta=0xc3402254, V=0x9b2e6ac9, real_isn=0xd7ee4875
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xfa624430
SERVERNIC: SYN-ACK: delta=0x1e87fd45, V=0xfa624430, real_isn=0xdbda46eb
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```

[1;33m[19:45:13] Starting 1 iperf2 server(s) on ports 8080-8080 ? press Ctrl+C to stop.[0m

[1;33m[19:45:13] iperf servers running (pids: 21765)[0m
------------------------------------------------------------
Server listening on TCP port 8080
TCP window size:  128 KByte (default)
------------------------------------------------------------
[  4] local 10.1.2.226 port 8080 connected with 10.1.0.31 port 60170
[  7] local 10.1.2.226 port 8080 connected with 10.1.0.31 port 60192
[  9] local 10.1.2.226 port 8080 connected with 10.1.0.31 port 60214
[  8] local 10.1.2.226 port 8080 connected with 10.1.0.31 port 60206
[  5] local 10.1.2.226 port 8080 connected with 10.1.0.31 port 60178
[ ID] Interval       Transfer     Bandwidth
[  9]  0.0- 7.1 sec  1.00 MBytes  1.18 Mbits/sec
[  4]  0.0- 7.8 sec  1.00 MBytes  1.08 Mbits/sec
[  7]  0.0-15.3 sec  1.00 MBytes   550 Kbits/sec
[  5]  0.0-17.8 sec  1.00 MBytes   471 Kbits/sec
[  8]  0.0-33.6 sec  1.00 MBytes   250 Kbits/sec
[SUM]  0.0-33.6 sec  5.00 MBytes  1.25 Mbits/sec
```

## Packet Analysis

```
metric=send_unlock value_ms=1.659 node=client flow=10.1.0.31:60170-10.1.2.226:8080
metric=fct value_ms=7993.500 node=client flow=10.1.0.31:60170-10.1.2.226:8080
metric=send_unlock value_ms=1.464 node=client flow=10.1.0.31:60178-10.1.2.226:8080
metric=fct value_ms=18027.951 node=client flow=10.1.0.31:60178-10.1.2.226:8080
metric=send_unlock value_ms=0.946 node=client flow=10.1.0.31:60192-10.1.2.226:8080
metric=fct value_ms=15463.031 node=client flow=10.1.0.31:60192-10.1.2.226:8080
metric=send_unlock value_ms=0.848 node=client flow=10.1.0.31:60206-10.1.2.226:8080
metric=fct value_ms=33808.578 node=client flow=10.1.0.31:60206-10.1.2.226:8080
metric=send_unlock value_ms=0.390 node=client flow=10.1.0.31:60214-10.1.2.226:8080
metric=fct value_ms=7346.312 node=client flow=10.1.0.31:60214-10.1.2.226:8080
missing=SYN-ACK flow=unknown
```
