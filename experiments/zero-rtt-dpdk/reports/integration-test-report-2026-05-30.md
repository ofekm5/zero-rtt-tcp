# Integration Test Report — 2026-05-30

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh`
**Node scripts**: `experiments/zero-rtt-dpdk/nodes/`
**Overall result**: 1 FAILURE(S) ❌

## Client Output

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.49:8080

  Connection 1: 2.28 ms

Results:
  Success: 1/1 (100%)
  TTFB Statistics:
    Min:     2.28 ms
    Max:     2.28 ms
    Average: 2.28 ms
    Median:  2.28 ms
```

## ClientNIC Log (0-RTT activity)

```
[1;33m[18:40:10] Killing any leftover clientnic-dpdk-forwarder/tcpdump processes...[0m
[1;33m[18:40:12] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:40:12] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[18:40:12] Using existing binary: /home/ec2-user/zero-rtt-demo/clientnic/dpdk-forwarder/builddir/clientnic-dpdk-forwarder[0m
[1;33m[18:40:12] Gateway MAC (ServerNIC eth1, Middle subnet DPDK port): 02:77:5c:47:e0:ed[0m
[1;33m[18:40:12] IP forwarding: enabled[0m
[1;33m[18:40:12] Starting tcpdump on eth0 ? /tmp/client_side.pcap ...[0m
[1;33m[18:40:13] Starting clientnic-dpdk-forwarder ? transparent forwarding with V-stamp. Press Ctrl+C to stop.[0m
[1;33m[18:40:13]   --port=8080 --gw-mac=02:77:5c:47:e0:ed[0m

EAL: Detected CPU lcores: 2
EAL: Detected NUMA nodes: 1
EAL: Detected shared linkage of DPDK
EAL: Multi-process socket /var/run/dpdk/rte/mp_socket
EAL: Selected IOVA mode 'PA'
EAL: VFIO support initialized
EAL: Cannot open /dev/vfio/noiommu-0: Device or resource busy
EAL: Failed to open VFIO group 0
EAL: Requested device 0000:00:06.0 cannot be used
TELEMETRY: No legacy callbacks, legacy socket not created
FORWARDER: ClientNIC DPDK Forwarder starting (port=8080, client=eth0, server=eth1)
FORWARDER: Gateway MAC: 02:77:5c:47:e0:ed
FORWARDER: No DPDK ports available (is eth1 bound to vfio-pci?)
```

## ServerNIC Log

```
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:39:56] SKIP_BUILD=1 ? skipping meson+ninja build.[0m
[1;33m[18:39:56] Using existing binary: /home/ec2-user/zero-rtt-demo/servernic/dpdk/builddir/servernic-dpdk[0m
[1;33m[18:39:56] ClientNIC-side gateway MAC (eth1): 02:8e:22:ca:e7:5f[0m
[1;33m[18:39:56] Server-side gateway MAC (eth2):    02:79:c9:50:e3:0d[0m
[1;33m[18:39:56] IP forwarding: enabled[0m
[1;33m[18:39:56] Starting servernic-dpdk ? watching for flows. Press Ctrl+C to stop.[0m
[1;33m[18:39:56]   --port=8080 --gw-mac=02:8e:22:ca:e7:5f --server-gw-mac=02:79:c9:50:e3:0d[0m

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
SERVERNIC: SYN: new flow, V=0x12407899
SERVERNIC: SYN-ACK: delta=0x34d95be8, V=0x12407899, real_isn=0xdd671cb1
SERVERNIC: SYN-ACK: flushed 2 buffered c2s packets
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```
[1;33m[18:39:47] Killing any leftover server.py...[0m
[1;33m[18:39:48] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[18:39:48] Server VM IP: 10.1.2.49[0m
[1;33m[18:39:48] Will listen on 0.0.0.0:8080[0m

[1;33m[18:39:48] Starting server.py ? press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
[10.1.0.188:36360] Received 22 bytes
[10.1.0.188:36360] Sent 40 bytes
```

## Packet Analysis

```
T8 mode: loading /tmp/client_side.pcap  (eth0 - client side)
  eth0: 15 packet(s)

  eth0 SYNs: 2
  eth0 SYN-ACKs: 1
    t=1780166424.042008  ISN=306215065  10.1.2.49:8080 -> 10.1.0.188:36360

-- A. Spoofed SYN-ACK on eth0 (T8 mode) ---------------------------------
[PASS] At least one SYN-ACK seen on eth0  (1 SYN-ACK(s))

-- B. No duplicate SYN-ACK per flow (real SYN-ACK dropped at ServerNIC) --
[PASS] Exactly one SYN-ACK per flow on eth0  (1 flow(s) OK)

-- C. 0-RTT Timing (informational) --------------------------------------
  flow dport=36360: SYN_t=1780166424.041982  SYN-ACK_t=1780166424.042008  OK
[PASS] SYN-ACK follows SYN in capture (informational)  (1/1 flows)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 15 packets valid)

------------------------------------------------------------
All checks passed.
```

## eBPF TCP Traces

### Client VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 2329744176961, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 0, "dport": 8080, "old_state": "TCP_CLOSE", "new_state": "TCP_SYN_SENT"}
{"ts_ns": 2329744561660, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 36360, "dport": 8080, "old_state": "TCP_SYN_SENT", "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 2329746419855, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 36360, "dport": 8080, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_CLOSE_WAIT"}
{"ts_ns": 2329746474572, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 36360, "dport": 8080, "old_state": "TCP_CLOSE_WAIT", "new_state": "TCP_LAST_ACK"}
{"ts_ns": 2329747304805, "src": "10.1.0.188", "dst": "10.1.2.49", "sport": 36360, "dport": 8080, "old_state": "TCP_LAST_ACK", "new_state": "TCP_CLOSE"}
```

### Server VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 2293995114568, "src": "0.0.0.0", "dst": "0.0.0.0", "sport": 8080, "dport": 0, "old_state": "TCP_CLOSE", "new_state": "TCP_LISTEN"}
{"ts_ns": 2329314703773, "src": "0.0.0.0", "dst": "0.0.0.0", "sport": 8080, "dport": 0, "old_state": "TCP_LISTEN", "new_state": "TCP_SYN_RECV"}
{"ts_ns": 2329314743872, "src": "10.1.2.49", "dst": "10.1.0.188", "sport": 8080, "dport": 36360, "old_state": "TCP_SYN_RECV", "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 2329315506775, "src": "10.1.2.49", "dst": "10.1.0.188", "sport": 8080, "dport": 36360, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_FIN_WAIT1"}
{"ts_ns": 2329316305567, "src": "10.1.2.49", "dst": "10.1.0.188", "sport": 8080, "dport": 36360, "old_state": "TCP_FIN_WAIT1", "new_state": "TCP_FIN_WAIT2"}
{"ts_ns": 2329316316647, "src": "10.1.2.49", "dst": "10.1.0.188", "sport": 8080, "dport": 36360, "old_state": "TCP_FIN_WAIT2", "new_state": "TCP_CLOSE"}
```
