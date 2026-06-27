# Integration Test Report — 2026-06-28

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 5 FAILURE(S)

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : no samples found
  Send unlock   : no samples found
  Server gap    : no samples found
```

## Client Output

```

```

## ClientNIC Log (0-RTT activity)

```
[1;33m[21:22:11] Killing any leftover clientnic-dpdk-forwarder/tcpdump processes...[0m
[1;33m[21:22:12] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
HEAD is now at bfc942c perf(dpdk): cap tx retries at 8 to avoid head-of-line collapse under load
[1;33m[21:22:13] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[21:22:13] Using existing binary: /home/ec2-user/zero-rtt-demo/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder[0m
[1;33m[21:22:13] Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): 02:68:54:04:73:6f[0m
[1;33m[21:22:13] IP forwarding: enabled[0m
[1;33m[21:22:13] Starting tcpdump on eth0 ? /tmp/client_side.pcap (ports 8080-8083) ...[0m
[1;33m[21:22:14] Starting clientnic-dpdk-forwarder ? transparent forwarding with V-stamp. Press Ctrl+C to stop.[0m
[1;33m[21:22:14]   --port=8080 --port-count=4 --gw-mac=02:68:54:04:73:6f[0m

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
FORWARDER: ClientNIC DPDK Forwarder starting (port=8080..8083, client=eth0, server=eth1)
FORWARDER: Gateway MAC: 02:68:54:04:73:6f
FORWARDER: eth0: initialized on eth0 (ifindex=2, MAC=02:3b:1b:37:9b:2f)
FORWARDER: eth1: DPDK port 0 started (MAC=02:8c:9c:66:6b:8d)
FORWARDER: Entering busy-poll loop...
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
 * branch            main       -> FETCH_HEAD
HEAD is now at bfc942c perf(dpdk): cap tx retries at 8 to avoid head-of-line collapse under load
[1;33m[21:21:58] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[21:21:58] Using existing binary: /home/ec2-user/zero-rtt-demo/servernic/dpdk/builddir/servernic-dpdk[0m
[1;33m[21:21:58] ClientNIC-side gateway MAC (eth1): 02:8c:9c:66:6b:8d[0m
[1;33m[21:21:58] Server-side gateway MAC (eth2):    02:89:24:06:2f:2b[0m
[1;33m[21:21:58] Checking DPDK binding (Middle subnet ENI should be vfio-pci)...[0m
[1;33m[21:21:58] Middle subnet ENI (02:68:54:04:73:6f) not in kernel ? already DPDK-bound, OK[0m
[1;33m[21:21:58] Server-facing interface (AF_PACKET): eth1[0m
[1;33m[21:21:58] IP forwarding: enabled[0m
[1;33m[21:21:58] Starting servernic-dpdk ? watching for flows. Press Ctrl+C to stop.[0m
[1;33m[21:21:58]   --port=8080 --port-count=4 --gw-mac=02:8c:9c:66:6b:8d --server-gw-mac=02:89:24:06:2f:2b[0m

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
SERVERNIC: ServerNIC DPDK starting (port=8080..8083, client-iface=eth1, server-iface=eth1)
SERVERNIC: eth1: DPDK port 0 started (MAC=02:68:54:04:73:6f)
SERVERNIC: eth2: initialized on eth1 (ifindex=5, MAC=02:4c:48:70:a3:3d)
SERVERNIC: Entering busy-poll loop...
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```

```

## Packet Analysis

```

```
