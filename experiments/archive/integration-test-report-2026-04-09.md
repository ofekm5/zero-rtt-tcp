# Integration Test Report — 2026-04-09

**Implementation**: DPDK
**Experiment script**: `experiments/zero-rtt-dpdk/run_experiment.sh`
**Node scripts**: `experiments/zero-rtt-dpdk/nodes/`
**Overall result**: 1 FAILURE(S) ❌

## Client Output

```
=== Repeated Connection Test (1 connections) ===
Server: 10.1.2.229:8080

  Connection 1: 275.87 ms

Results:
  Success: 1/1 (100%)
  TTFB Statistics:
    Min:     275.87 ms
    Max:     275.87 ms
    Average: 275.87 ms
    Median:  275.87 ms
```

## ClientNIC Log (0-RTT activity)

```

```

## ServerNIC Log

```
 * branch            main       -> FETCH_HEAD
error: Your local changes to the following files would be overwritten by merge:
	README.md
	clientnic/README.md
Please commit your changes or stash them before you merge.
Aborting
Updating 9cf3c8a..f15bb4a
[1;33m[13:47:50] Adding route 10.1.0.0/24 via 10.1.1.1 dev eth0...[0m
[1;33m[13:47:50] Setting iptables FORWARD DROP for port 8080...[0m
[1;33m[13:47:51] IP forwarding: enabled[0m
[1;33m[13:47:51] Starting servernic/scapy/main.py � press Ctrl+C to stop.[0m

[INFO] servernic: Starting ServerNIC...
[INFO] servernic: Forwarding between eth0 (ClientNIC) <-> eth1 (Server)
[INFO] servernic: Sniffing on [eth0, eth1] with filter: tcp port 8080 and not host 169.254.169.254
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [SYN]
/usr/local/lib/python3.7/site-packages/scapy/sendrecv.py:488: SyntaxWarning: 'iface' has no effect on L3 I/O send(). For multicast/link-local see https://scapy.readthedocs.io/en/latest/usage.html#multicast
  SyntaxWarning,
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [SYN-ACK]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK-PSH]
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [ACK]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK-PSH]
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [ACK-PSH]
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [ACK-FIN]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK]
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [ACK]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK-FIN]
[INFO] servernic: ClientNIC -> Server  10.1.0.74:58092 -> 10.1.2.229:8080 [ACK]
[INFO] servernic: Server -> ClientNIC  10.1.2.229:8080 -> 10.1.0.74:58092 [ACK]
```

## Server Log

```
[1;33m[13:47:37] Killing any leftover server.py...[0m
[1;33m[13:47:38] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
error: Your local changes to the following files would be overwritten by merge:
	README.md
	clientnic/README.md
Please commit your changes or stash them before you merge.
Aborting
Updating 9cf3c8a..f15bb4a
[1;33m[13:47:39] Server VM IP: 10.1.2.229[0m
[1;33m[13:47:39] Will listen on 0.0.0.0:8080[0m

[1;33m[13:47:39] Starting server.py � press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
[10.1.0.74:58092] Received 22 bytes
[10.1.0.74:58092] Sent 40 bytes
```

## Packet Analysis

```
Loading /tmp/client_side.pcap  (eth0 - client side)
Loading /tmp/server_side.pcap  (eth1 - server side)
  eth0: 13 packet(s)
  eth1: 7 packet(s)

  eth0 SYN-ACKs: 1
    t=1775742503.614698  ISN=475318164  10.1.2.229:8080 -> 10.1.0.74:58092

  eth1 SYN-ACKs: 1
    t=1775742503.728131  ISN=2269566357  10.1.2.229:8080 -> 10.1.0.74:58092

-- A. Spoofed SYN-ACK Detection -----------------------------------------
  Real ISNs seen on eth1: [2269566357]
  Spoofed SYN-ACKs on eth0 (ISN not in real set): 1
  Forwarded-real SYN-ACKs on eth0 (ISN in real set): 0
[PASS] Real SYN-ACK(s) found on eth1  (1 SYN-ACK(s))
[PASS] Spoofed SYN-ACK(s) found on eth0 (distinct ISN)  (1 spoofed, 0 forwarded-real)

-- B. ISN Delta ---------------------------------------------------------
  flow dport=58092: spoofed_ISN=475318164  real_ISN=2269566357  delta=2500719103
[PASS] All deltas are non-zero  (1 matched flow(s))

-- C. 0-RTT Timing (informational) -------------------------------------
  flow dport=58092: spoofed_t=1775742503.614698  real_t=1775742503.728131  delta=0.113s  OK (spoofed earlier)
[PASS] Spoofed SYN-ACK arrives before real (informational)  (1/1 flows -- NOTE: intra-VPC RTT may be faster than Python/Scapy processing)

-- D. Checksum Validation -----------------------------------------------
[PASS] No bad checksums on eth0 (client side)  (all 13 packets valid)
[PASS] No bad checksums on eth1 (server side)  (all 7 packets valid)

------------------------------------------------------------
All checks passed.
```

## eBPF TCP Traces

### Client VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 1097159299231, "src": "10.1.0.74", "dst": "10.1.2.229", "sport": 0, "dport": 8080, "old_state": "TCP_CLOSE", "new_state": "TCP_SYN_SENT"}
{"ts_ns": 1097160838006, "src": "10.1.0.74", "dst": "10.1.2.229", "sport": 58092, "dport": 8080, "old_state": "TCP_SYN_SENT", "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 1097435211461, "src": "10.1.0.74", "dst": "10.1.2.229", "sport": 58092, "dport": 8080, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_FIN_WAIT1"}
{"ts_ns": 1097466920862, "src": "10.1.0.74", "dst": "10.1.2.229", "sport": 58092, "dport": 8080, "old_state": "TCP_FIN_WAIT1", "new_state": "TCP_CLOSING"}
{"ts_ns": 1097626997037, "src": "10.1.0.74", "dst": "10.1.2.229", "sport": 58092, "dport": 8080, "old_state": "TCP_CLOSING", "new_state": "TCP_CLOSE"}
```

### Server VM — TCP State Transitions

```json
Attaching 3 probes...
{"ts_ns": 1054178337065, "src": "0.0.0.0", "dst": "0.0.0.0", "sport": 8080, "dport": 0, "old_state": "TCP_CLOSE", "new_state": "TCP_LISTEN"}
{"ts_ns": 1098386732526, "src": "0.0.0.0", "dst": "0.0.0.0", "sport": 8080, "dport": 0, "old_state": "TCP_LISTEN", "new_state": "TCP_SYN_RECV"}
{"ts_ns": 1098386762150, "src": "10.1.2.229", "dst": "10.1.0.74", "sport": 8080, "dport": 58092, "old_state": "TCP_SYN_RECV", "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 1098419089789, "src": "10.1.2.229", "dst": "10.1.0.74", "sport": 8080, "dport": 58092, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_FIN_WAIT1"}
{"ts_ns": 1098642971627, "src": "10.1.2.229", "dst": "10.1.0.74", "sport": 8080, "dport": 58092, "old_state": "TCP_FIN_WAIT1", "new_state": "TCP_CLOSING"}
{"ts_ns": 1098674708989, "src": "10.1.2.229", "dst": "10.1.0.74", "sport": 8080, "dport": 58092, "old_state": "TCP_CLOSING", "new_state": "TCP_CLOSE"}
```
