# Integration Test Report — 2026-07-25

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `src/clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `src/servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: 1 FAILURE(S)

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : n=143  min=16037.647  mean=16042.805  median=16042.734  max=16048.904 ms
  Send unlock   : n=144  min=16031.818  mean=16033.750  median=16033.779  max=16035.737 ms
  Server gap    : n=277  min=15973.667  mean=16009.819  median=16007.544  max=16035.586 ms
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 100000 total connections, 4096 bytes/conn ---
Transfer complete: 68779/100000 connections ok, 31221 failed, duration=142.775s, ~15.8 Mbits/sec
Success: 68779/100000
Success: 0/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x31069f98 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xde8942eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe7eb56a1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1dd4d502 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf5b96fac in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x24accff1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x414263bb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7cde02de in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf47b0f1f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf547cbc2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x61ef3ecd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8dbae168 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x932087a2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x628228b1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe95b743a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc636d349 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xda013a97 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa3e5a46a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8744b349 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1f7fa379 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe70b65f7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x496c0f64 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x156df218 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0a553386 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x28894da4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb955a879 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcb266639 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x347c8b08 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0c178be7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd68ebb0a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x53ba15ab in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcb291be6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcd3c9672 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd6b23825 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9b64bbcd in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb24b69aa in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x077375f3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb6b73057 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7f036449 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe80fb8d7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf399ff26 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd69e57eb in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x760cd00c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xf6cd8f2b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x040eca76 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbd13a0b5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x93187ce9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3aa2e9b2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1f6ab7de in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6f849deb in ack-nu--output truncated--
```

## ServerNIC Log

```
SERVERNIC: SYN: new flow, V=0x0770c43c
SERVERNIC: SYN-ACK: delta=0x391e6529, V=0x8ebea2c5, real_isn=0x55a03d9c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xfda98390
SERVERNIC: SYN: new flow, V=0x0cc52c10
SERVERNIC: SYN: new flow, V=0x6b6c7489
SERVERNIC: SYN-ACK: delta=0xbd173a32, V=0xa87de5a4, real_isn=0xeb66ab72
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0x1beccc25, V=0x505bd371, real_isn=0x346f074c
SERVERNIC: SYN-ACK: delta=0x3b26e29e, V=0xc611a524, real_isn=0x8aeac286
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x36b9021d
SERVERNIC: SYN-ACK: delta=0xd5adf501, V=0x0770c43c, real_isn=0x31c2cf3b
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x6dcb441e
SERVERNIC: SYN-ACK: delta=0x16601934, V=0xfda98390, real_isn=0xe7496a5c
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x48afac6d
SERVERNIC: SYN-ACK: delta=0xc6f7e481, V=0x0cc52c10, real_isn=0x45cd478f
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x090e07e9
SERVERNIC: SYN-ACK: delta=0x83d92763, V=0x6b6c7489, real_isn=0xe7934d26
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x408a3c73
SERVERNIC: SYN: new flow, V=0x79273f43
SERVERNIC: SYN-ACK: delta=0xad8aa794, V=0x6dcb441e, real_isn=0xc0409c8a
SERVERNIC: SYN-ACK: delta=0xa3bf3604, V=0x36b9021d, real_isn=0x92f9cc19
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xef24f101
SERVERNIC: SYN: new flow, V=0xf392--output truncated--
```

## Server Log

```
[1;33m[18:12:24] Killing any leftover load-generator processes...[0m
[1;33m[18:12:25] Open-file limit (ulimit -n): 1048576[0m
[1;33m[18:12:25] Syncing code to origin/main (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            main       -> FETCH_HEAD
HEAD is now at 58f11c3 Measure cycles_per_packet against offered load; raise pcap-analysis timeout for 100k-scale captures
[1;33m[18:12:26] Server VM IP: 10.1.2.143[0m
[1;33m[18:12:26] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[18:12:26] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Listening on ports [8080, 8081, 8082, 8083]
Received 38715392 bytes across 9452 connections (so far)
Received 122867712 bytes across 29997 connections (so far)
Received 161480704 bytes across 39424 connections (so far)
Received 161566720 bytes across 39445 connections (so far)
```

## Packet Analysis

```
metric=send_unlock value_ms=16035.737 node=client flow=10.1.0.178:9226-10.1.2.143:8080
metric=fct value_ms=16038.201 node=client flow=10.1.0.178:9226-10.1.2.143:8080
metric=send_unlock value_ms=16035.699 node=client flow=10.1.0.178:53158-10.1.2.143:8081
metric=fct value_ms=16037.712 node=client flow=10.1.0.178:53158-10.1.2.143:8081
metric=send_unlock value_ms=16035.628 node=client flow=10.1.0.178:3466-10.1.2.143:8082
metric=fct value_ms=16037.986 node=client flow=10.1.0.178:3466-10.1.2.143:8082
metric=send_unlock value_ms=16035.610 node=client flow=10.1.0.178:36622-10.1.2.143:8083
metric=fct value_ms=16037.944 node=client flow=10.1.0.178:36622-10.1.2.143:8083
metric=send_unlock value_ms=16035.589 node=client flow=10.1.0.178:9236-10.1.2.143:8080
metric=fct value_ms=16037.849 node=client flow=10.1.0.178:9236-10.1.2.143:8080
metric=send_unlock value_ms=16035.526 node=client flow=10.1.0.178:53162-10.1.2.143:8081
metric=fct value_ms=16037.771 node=client flow=10.1.0.178:53162-10.1.2.143:8081
metric=send_unlock value_ms=16035.476 node=client flow=10.1.0.178:3470-10.1.2.143:8082
metric=fct value_ms=16037.700 node=client flow=10.1.0.178:3470-10.1.2.143:8082
metric=send_unlock value_ms=16035.452 node=client flow=10.1.0.178:36624-10.1.2.143:8083
metric=fct value_ms=16037.647 node=client flow=10.1.0.178:36624-10.1.2.143:8083
metric=send_unlock value_ms=16035.439 node=client flow=10.1.0.178:9244-10.1.2.143:8080
metric=fct value_ms=16038.272 node=client flow=10.1.0.178:9244-10.1.2.143:8080
metric=send_unlock value_ms=16035.472 node=client flow=10.1.0.178:53170-10.1.2.143:8081
metric=fct value_ms=16038.247 node=client flow=10.1.0.178:53170-10.1.2.143:8081
metric=send_unlock value_ms=16035.345 node=client flow=10.1.0.178:3486-10.1.2.143:8082
metric=fct value_ms=16038.165 node=client flow=10.1.0.178:3486-10.1.2.143:8082
metric=send_unlock value_ms=16035.367 node=client flow=10.1.0.178:36634-10.1.2.143:8083
metric=fct value_ms=16038.107 node=client flow=10.1.0.178:36634-10.1.2.143:8083
metric=send_unlock value_ms=16035.335 node=client flow=10.1.0.178:9256-10.1.2.143:8080
metric=fct value_ms=16038.086 node=client flow=10.1.0.178:9256-10.1.2.143:8080
metric=send_unlock value_ms=16035.298 node=client flow=10.1.0.178:53176-10.1.2.143:8081
metric=fct value_ms=16038.007 node=client flow=10.1.0.178:53176-10.1.2.143:8081
metric=send_unlock value_ms=16035.248 node=client flow=10.1.0.178:3500-10.1.2.143:8082
metric=fct value_ms=16039.014 node=client flow=10.1.0.178:3500-10.1.2.143:8082
metric=send_unlock value_ms=16035.208 node=client flow=10.1.0.178:36646-10.1.2.143:8083
metric=fct value_ms=16038.899 node=client flow=10.1.0.178:36646-10.1.2.143:8083
metric=send_unlock value_ms=16035.210 node=client flow=10.1.0.178:9270-10.1.2.143:8080
metric=fct value_ms=16038.872 node=client flow=10.1.0.178:9270-10.1.2.143:8080
metric=send_unlock value_ms=16035.238 node=client flow=10.1.0.178:53192-10.1.2.143:8081
metric=fct value_ms=16038.796 node=client flow=10.1.0.178:53192-10.1.2.143:8081
metric=send_unlock value_ms=16035.008 node=client flow=10.1.0.178:3510-10.1.2.143:8082
metric=fct value_ms=16038.684 node=client flow=10.1.0.178:3510-10.1.2.143:8082
metric=send_unlock value_ms=16035.166 node=client flow=10.1.0.178:36650-10.1.2.143:8083
metric=fct value_ms=16038.684 node=client flow=10.1.0.178:36650-10.1.2.143:8083
metric=send_unlock value_ms=16035.135 node=client flow=10.1.0.178:9278-10.1.2.143:8080
metric=fct value_ms=16038.628 node=client flow=10.1.0.178:9278-10.1.2.143:8080
metric=send_unlock value_ms=16035.023 node=client flow=10.1.0.178:53194-10.1.2.143:8081
metric=fct value_ms=16038.527 node=client flow=10.1.0.178:53194-10.1.2.143:8081
metric=send_unlock value_ms=16035.003 node=client flow=10.1.0.178:3526-10.1.2.143:8082
metric=fct value_ms=16038.440 node=client flow=10.1.0.178:3526-10.1.2.143:8082
metric=send_unlock value_ms=16035.065 node=client flow=10.1.0.178:36652-10.1.2.143:8083
metric=fct value_ms=16039.715 node=client flow=10.1.0.178:36652-10.1.2.143:8083
metric=send_unlock value_ms=16035.050 node=client flow=10.1.0.178:9280-10.1.2.143:8080
metric=fct value_ms=16039.649 node=client flow=10.1.0.178:9280-10.1.2.143:8080
metric=send_unlock value_ms=16034.872 node=client flow=10.1.0.178:53204-10.1.2.143:8081
metric=fct value_ms=16039.521 node=client flow=10.1.0.178:53204-10.1.2.143:8081
metric=send_unlock value_ms=16034.963 node=client flow=10.1.0.178:3542-10.1.2.143:8082
metric=fct value_ms=16039.496 node=client flow=10.1.0.178:3542-10.1.2.143:8082
metric=send_unlock value_ms=16034.950 node=client flow=10.1.0.178:36660-10.1.2.143:8083
metric=fct value_ms=16039.407 node=client flow=10.1.0.178:36660-10.1.2.143:8083
metric=send_unlock value_ms=16035.040 node=client flow=10.1.0.178:9288-10.1.2.143:8080
metric=fct value_ms=16039.431 node=client flow=10.1.0.178:9288-10.1.2.143:8080
metric=send_unlock value_ms=16034.840 node=client flow=10.1.0.178:53220-10.1.2.143:8081
metric=fct value_ms=16039.302 node=client flow=10.1.0.178:53220-10.1.2.143:8081
metric=send_unlock value_ms=16034.798 node=client flow=10.1.0.178:3548-10.1.2.143:8082
metric=fct value_ms=16039.209 node=client flow=10.1.0.178:3548-10.1.2.143:8082
metric=send_unlock value_ms=16034.802 node=client flow=10.1.0.178:36676-10.1.2.143:8083
metric=fct value_ms=16040.898 node=client flow=10.1.0.178:36676-10.1.2.143:8083
metric=send_unlock value_ms=16034.777 node=client flow=10.1.0.178:9300-10.1.2.143:8080
metric=fct value_ms=16040.789 node=client flow=10.1.0.178:9300-10.1.2.143:8080
metric=send_unlock value_ms=16034.751 node=client flow=10.1.0.178:53226-10.1.2.143:8081
metric=fct value_ms=16040.781 node=client flow=10.1.0.178:53226-10.1.2.143:8081
metric=send_unlock value_ms=16034.744 node=client flow=10.1.0.178:3556-10.1.2.143:8082
metric=fct value_ms=16040.725 node=client flow=10.1.0.178:3556-10.1.2.143:8082
metric=send_unlock value_ms=16034.716 node=client flow=10.1.0.178:36692-10.1.2.143:8083
metric=fct value_ms=16040.667 node=client flow=10.1.0.178:36692-10.1.2.143:8083
metric=send_unlock value_ms=16034.668 node=client flow=10.1.0.178:9308-10.1.2.143:8080
metric=fct value_ms=16040.598 node=client flow=10.1.0.178:9308-10.1.2.143:8080
metric=send_unlock value_ms=16034.611 node=client flow=10.1.0.178:53232-10.1.2.143:8081
metric=fct value_ms=16040.489 node=client flow=10.1.0.178:53232-10.1.2.143:8081
metric=send_unlock value_ms=16034.581 node=client flow=10.1.0.178:3564-10.1.2.143:8082
metric=fct value_ms=16040.495 node=client flow=10.1.0.178:3564-10.1.2.143:8082
metric=send_unlock value_ms=16034.543 node=client flow=10.1.0.178:36698-10.1.2.143:8083
metric=fct value_ms=16040.418 node=client flow=10.1.0.178:36698-10.1.2.143:8083
metric=send_unlock value_ms=16034.511 node=client flow=10.1.0.178:9320-10.1.2.143:8080
metric=fct value_ms=16040.321 node=client flow=10.1.0.178:9320-10.1.2.143:8080
metric=send_unlock value_ms=16034.496 node=client flow=10.1.0.178:53248-10.1.2.143:8081
metric=fct value_ms=16040.261 node=client flow=10.1.0.178:53248-10.1.2.143:8081
metric=send_unlock value_ms=16034.479 node=client flow=10.1.0.178:3578-10.1.2.143:8082
metric=fct value_ms=16040.209 node=client flow=10.1.0.178:3578-10.1.2.143:8082
metric=send_unlock value_ms=16034.496 node=client flow=10.1.0.178:36706-10.1.2.143:8083
metric=fct value_ms=16040.206 node=client flow=10.1.0.178:36706-10.1.2.143:8083
metric=send_unlock value_ms=16034.389 node=client flow=10.1.0.178:9330-10.1.2.143:8080
metric=fct value_ms=16040.120 node=client flow=10.1.0.178:9330-10.1.2.143:8080
metric=send_unlock value_ms=16034.377 node=client flow=10.1.0.178:53262-10.1.2.143:8081
metric=fct value_ms=16040.042 node=client flow=10.1.0.178:53262-10.1.2.143:8081
metric=send_unlock value_ms=16034.375 node=client flow=10.1.0.178:3588-10.1.2.143:8082
metric=fct value_ms=16042.279 node=client flow=10.1.0.178:3588-10.1.2.143:8082
metric=send_unlock value_ms=16034.342 node=client flow=10.1.0.178:36720-10.1.2.143:8083
metric=fct value_ms=16042.266 node=client flow=10.1.0.178:36720-10.1.2.143:8083
metric=send_unlock value_ms=16034.415 node=client flow=10.1.0.178:9346-10.1.2.143:8080
metric=fct value_ms=16042.141 node=client flow=10.1.0.178:9346-10.1.2.143:8080
metric=send_unlock value_ms=16034.396 node=client flow=10.1.0.178:53266-10.1.2.143:8081
metric=fct value_ms=16042.120 node=client flow=10.1.0.178:53266-10.1.2.143:8081
metric=send_unlock value_ms=16034.200 node=client flow=10.1.0.178:3590-10.1.2.143:8082
metric=fct value_ms=16042.017 node=client flow=10.1.0.178:3590-10.1.2.143:8082
metric=send_unlock value_ms=16034.353 node=client flow=10.1.0.178:36726-10.1.2.143:8083
metric=fct value_ms=16041.969 node=client flow=10.1.0.178:36726-10.1.2.143:8083
metric=send_unlock value_ms=16034.249 node=client flow=10.1.0.178:9360-10.1.2.143:8080
metric=fct value_ms=16041.917 node=client flow=10.1.0.178:9360-10.1.2.143:8080
metric=send_unlock value_ms=16034.280 node=client flow=10.1.0.178:53280-10.1.2.143:8081
metric=fct value_ms=16041.984 node=client flow=10.1.0.178:53280-10.1.2.143:8081
metric=send_unlock value_ms=16034.263 node=client flow=10.1.0.178:3604-10.1.2.143:8082
metric=fct value_ms=16041.853 node=client flow=10.1.0.178:3604-10.1.2.143:8082
metric=send_unlock value_ms=16034.135 node=client flow=10.1.0.178:36738-10.1.2.143:8083
metric=fct value_ms=16041.690 node=client flow=10.1.0.178:36738-10.1.2.143:8083
metric=send_unlock value_ms=16034.131 node=client flow=10.1.0.178:9376-10.1.2.143:8080
metric=fct value_ms=16041.724 node=client flow=10.1.0.178:9376-10.1.2.143:8080
metric=send_unlock value_ms=16034.086 node=client flow=10.1.0.178:53288-10.1.2.143:8081
metric=fct value_ms=16041.606 node=client flow=10.1.0.178:53288-10.1.2.143:8081
metric=send_unlock value_ms=16034.070 node=client flow=10.1.0.178:3618-10.1.2.143:8082
metric=fct value_ms=16041.555 node=client flow=10.1.0.178:3618-10.1.2.143:8082
metric=send_unlock value_ms=16034.045 node=client flow=10.1.0.178:36744-10.1.2.143:8083
metric=fct value_ms=16041.495 node=client flow=10.1.0.178:36744-10.1.2.143:8083
metric=send_unlock value_ms=16034.069 node=client flow=10.1.0.178:9380-10.1.2.143:8080
metric=fct value_ms=16041.509 node=client flow=10.1.0.178:9380-10.1.2.143:8080
metric=send_unlock value_ms=16034.040 node=client flow=10.1.0.178:53296-10.1.2.143:8081
metric=fct value_ms=16041.506 node=client flow=10.1.0.178:53296-10.1.2.143:8081
metric=send_unlock value_ms=16033.872 node=client flow=10.1.0.178:3626-10.1.2.143:8082
metric=fct value_ms=16041.326 node=client flow=10.1.0.178:3626-10.1.2.143:8082
metric=send_unlock value_ms=16033.895 node=client flow=10.1.0.178:36758-10.1.2.143:8083
metric=fct value_ms=16041.308 node=client flow=10.1.0.178:36758-10.1.2.143:8083
metric=send_unlock value_ms=16033.879 node=client flow=10.1.0.178:9394-10.1.2.143:8080
metric=fct value_ms=16041.204 node=client flow=10.1.0.178:9394-10.1.2.143:8080
metric=send_unlock value_ms=16033.870 node=client flow=10.1.0.178:53308-10.1.2.143:8081
metric=fct value_ms=16041.218 node=client flow=10.1.0.178:53308-10.1.2.143:8081
metric=send_unlock value_ms=16033.878 node=client flow=10.1.0.178:3638-10.1.2.143:8082
metric=fct value_ms=16041.105 node=client flow=10.1.0.178:3638-10.1.2.143:8082
metric=send_unlock value_ms=16033.876 node=client flow=10.1.0.178:36764-10.1.2.143:8083
metric=fct value_ms=16043.905 node=client flow=10.1.0.178:36764-10.1.2.143:8083
metric=send_unlock value_ms=16033.849 node=client flow=10.1.0.178:9408-10.1.2.143:8080
metric=fct value_ms=16043.877 node=client flow=10.1.0.178:9408-10.1.2.143:8080
metric=send_unlock value_ms=16033.829 node=client flow=10.1.0.178:53314-10.1.2.143:8081
metric=fct value_ms=16043.819 node=client flow=10.1.0.178:53314-10.1.2.143:8081
metric=send_unlock value_ms=16033.813 node=client flow=10.1.0.178:3652-10.1.2.143:8082
metric=fct value_ms=16043.813 node=client flow=10.1.0.178:3652-10.1.2.143:8082
metric=send_unlock value_ms=16033.842 node=client flow=10.1.0.178:36778-10.1.2.143:8083
metric=fct value_ms=16043.851 node=client flow=10.1.0.178:36778-10.1.2.143:8083
metric=send_unlock value_ms=16033.664 node=client flow=10.1.0.178:9416-10.1.2.143:8080
metric=fct value_ms=16043.633 node=client flow=10.1.0.178:9416-10.1.2.143:8080
metric=send_unlock value_ms=16033.684 node=client flow=10.1.0.178:53330-10.1.2.143:8081
metric=fct value_ms=16043.638 node=client flow=10.1.0.178:53330-10.1.2.143:8081
metric=send_unlock value_ms=16033.744 node=client flow=10.1.0.178:3658-10.1.2.143:8082
metric=fct value_ms=16043.643 node=client flow=10.1.0.178:3658-10.1.2.143:8082
metric=send_unlock value_ms=16033.588 node=client flow=10.1.0.178:36784-10.1.2.143:8083
metric=fct value_ms=16043.505 node=client flow=10.1.0.178:36784-10.1.2.143:8083
metric=send_unlock value_ms=16033.543 node=client flow=10.1.0.178:9426-10.1.2.143:8080
metric=fct value_ms=16043.522 node=client flow=10.1.0.178:9426-10.1.2.143:8080
metric=send_unlock value_ms=16033.556 node=client flow=10.1.0.178:53340-10.1.2.143:8081
metric=fct value_ms=16043.404 node=client flow=10.1.0.178:53340-10.1.2.143:8081
metric=send_unlock value_ms=16033.517 node=client flow=10.1.0.178:3666-10.1.2.143:8082
metric=fct value_ms=16043.351 node=client flow=10.1.0.178:3666-10.1.2.143:8082
metric=send_unlock value_ms=16033.533 node=client flow=10.1.0.178:36786-10.1.2.143:8083
metric=fct value_ms=16043.281 node=client flow=10.1.0.178:36786-10.1.2.143:8083
metric=send_unlock value_ms=16033.522 node=client flow=10.1.0.178:9430-10.1.2.143:8080
metric=fct value_ms=16043.215 node=client flow=10.1.0.178:9430-10.1.2.143:8080
metric=send_unlock value_ms=16033.479 node=client flow=10.1.0.178:53354-10.1.2.143:8081
metric=fct value_ms=16043.178 node=client flow=10.1.0.178:53354-10.1.2.143:8081
metric=send_unlock value_ms=16033.427 node=client flow=10.1.0.178:3676-10.1.2.143:8082
metric=fct value_ms=16043.087 node=client flow=10.1.0.178:3676-10.1.2.143:8082
metric=send_unlock value_ms=16033.423 node=client flow=10.1.0.178:36798-10.1.2.143:8083
metric=fct value_ms=16043.019 node=client flow=10.1.0.178:36798-10.1.2.143:8083
metric=send_unlock value_ms=16033.389 node=client flow=10.1.0.178:9436-10.1.2.143:8080
metric=fct value_ms=16042.961 node=client flow=10.1.0.178:9436-10.1.2.143:8080
metric=send_unlock value_ms=16033.380 node=client flow=10.1.0.178:53360-10.1.2.143:8081
metric=fct value_ms=16042.902 node=client flow=10.1.0.178:53360-10.1.2.143:8081
metric=send_unlock value_ms=16033.475 node=client flow=10.1.0.178:3692-10.1.2.143:8082
metric=fct value_ms=16042.871 node=client flow=10.1.0.178:3692-10.1.2.143:8082
metric=send_unlock value_ms=16033.288 node=client flow=10.1.0.178:36812-10.1.2.143:8083
metric=fct value_ms=16042.819 node=client flow=10.1.0.178:36812-10.1.2.143:8083
metric=send_unlock value_ms=16033.291 node=client flow=10.1.0.178:9442-10.1.2.143:8080
metric=fct value_ms=16042.734 node=client flow=10.1.0.178:9442-10.1.2.143:8080
metric=send_unlock value_ms=16033.298 node=client flow=10.1.0.178:53362-10.1.2.143:8081
metric=fct value_ms=16042.680 node=client flow=10.1.0.178:53362-10.1.2.143:8081
metric=send_unlock value_ms=16033.304 node=client flow=10.1.0.178:3706-10.1.2.143:8082
metric=fct value_ms=16042.627 node=client flow=10.1.0.178:3706-10.1.2.143:8082
metric=send_unlock value_ms=16033.148 node=client flow=10.1.0.178:36818-10.1.2.143:8083
metric=fct value_ms=16042.519 node=client flow=10.1.0.178:36818-10.1.2.143:8083
metric=send_unlock value_ms=16033.181 node=client flow=10.1.0.178:9450-10.1.2.143:8080
metric=fct value_ms=16042.430 node=client flow=10.1.0.178:9450-10.1.2.143:8080
metric=send_unlock value_ms=16033.157 node=client flow=10.1.0.178:53372-10.1.2.143:8081
metric=fct value_ms=16046.042 node=client flow=10.1.0.178:53372-10.1.2.143:8081
metric=send_unlock value_ms=16033.137 node=client flow=10.1.0.178:3722-10.1.2.143:8082
metric=fct value_ms=16046.031 node=client flow=10.1.0.178:3722-10.1.2.143:8082
metric=send_unlock value_ms=16033.084 node=client flow=10.1.0.178:36828-10.1.2.143:8083
metric=fct value_ms=16045.969 node=client flow=10.1.0.178:36828-10.1.2.143:8083
metric=send_unlock value_ms=16033.060 node=client flow=10.1.0.178:9454-10.1.2.143:8080
metric=fct value_ms=16045.918 node=client flow=10.1.0.178:9454-10.1.2.143:8080
metric=send_unlock value_ms=16033.117 node=client flow=10.1.0.178:53386-10.1.2.143:8081
metric=fct value_ms=16045.905 node=client flow=10.1.0.178:53386-10.1.2.143:8081
metric=send_unlock value_ms=16033.094 node=client flow=10.1.0.178:3732-10.1.2.143:8082
metric=fct value_ms=16045.831 node=client flow=10.1.0.178:3732-10.1.2.143:8082
metric=send_unlock value_ms=16032.926 node=client flow=10.1.0.178:36842-10.1.2.143:8083
metric=fct value_ms=16045.710 node=client flow=10.1.0.178:36842-10.1.2.143:8083
metric=send_unlock value_ms=16033.018 node=client flow=10.1.0.178:9462-10.1.2.143:8080
metric=fct value_ms=16045.711 node=client flow=10.1.0.178:9462-10.1.2.143:8080
metric=send_unlock value_ms=16033.038 node=client flow=10.1.0.178:53388-10.1.2.143:8081
metric=fct value_ms=16045.764 node=client flow=10.1.0.178:53388-10.1.2.143:8081
metric=send_unlock value_ms=16033.019 node=client flow=10.1.0.178:3746-10.1.2.143:8082
metric=fct value_ms=16045.655 node=client flow=10.1.0.178:3746-10.1.2.143:8082
metric=send_unlock value_ms=16032.992 node=client flow=10.1.0.178:36858-10.1.2.143:8083
metric=fct value_ms=16045.751 node=client flow=10.1.0.178:36858-10.1.2.143:8083
metric=send_unlock value_ms=16032.958 node=client flow=10.1.0.178:9476-10.1.2.143:8080
metric=fct value_ms=16045.678 node=client flow=10.1.0.178:9476-10.1.2.143:8080
metric=send_unlock value_ms=16032.939 node=client flow=10.1.0.178:53404-10.1.2.143:8081
metric=fct value_ms=16045.612 node=client flow=10.1.0.178:53404-10.1.2.143:8081
metric=send_unlock value_ms=16032.958 node=client flow=10.1.0.178:3748-10.1.2.143:8082
metric=fct value_ms=16045.587 node=client flow=10.1.0.178:3748-10.1.2.143:8082
metric=send_unlock value_ms=16032.778 node=client flow=10.1.0.178:36862-10.1.2.143:8083
metric=fct value_ms=16045.424 node=client flow=10.1.0.178:36862-10.1.2.143:8083
metric=send_unlock value_ms=16032.792 node=client flow=10.1.0.178:9484-10.1.2.143:8080
metric=fct value_ms=16045.348 node=client flow=10.1.0.178:9484-10.1.2.143:8080
metric=send_unlock value_ms=16032.770 node=client flow=10.1.0.178:53408-10.1.2.143:8081
metric=fct value_ms=16045.312 node=client flow=10.1.0.178:53408-10.1.2.143:8081
metric=send_unlock value_ms=16032.766 node=client flow=10.1.0.178:3762-10.1.2.143:8082
metric=fct value_ms=16045.241 node=client flow=10.1.0.178:3762-10.1.2.143:8082
metric=send_unlock value_ms=16032.731 node=client flow=10.1.0.178:36878-10.1.2.143:8083
metric=fct value_ms=16045.188 node=client flow=10.1.0.178:36878-10.1.2.143:8083
metric=send_unlock value_ms=16032.719 node=client flow=10.1.0.178:9488-10.1.2.143:8080
metric=fct value_ms=16045.127 node=client flow=10.1.0.178:9488-10.1.2.143:8080
metric=send_unlock value_ms=16032.796 node=client flow=10.1.0.178:53424-10.1.2.143:8081
metric=fct value_ms=16045.075 node=client flow=10.1.0.178:53424-10.1.2.143:8081
metric=send_unlock value_ms=16032.629 node=client flow=10.1.0.178:3764-10.1.2.143:8082
metric=fct value_ms=16044.937 node=client flow=10.1.0.178:3764-10.1.2.143:8082
metric=send_unlock value_ms=16032.682 node=client flow=10.1.0.178:36890-10.1.2.143:8083
metric=fct value_ms=16044.913 node=client flow=10.1.0.178:36890-10.1.2.143:8083
metric=send_unlock value_ms=16032.708 node=client flow=10.1.0.178:9502-10.1.2.143:8080
metric=fct value_ms=16044.842 node=client flow=10.1.0.178:9502-10.1.2.143:8080
metric=send_unlock value_ms=16032.586 node=client flow=10.1.0.178:53432-10.1.2.143:8081
metric=fct value_ms=16044.772 node=client flow=10.1.0.178:53432-10.1.2.143:8081
metric=send_unlock value_ms=16032.594 node=client flow=10.1.0.178:3772-10.1.2.143:8082
metric=fct value_ms=16044.709 node=client flow=10.1.0.178:3772-10.1.2.143:8082
metric=send_unlock value_ms=16032.568 node=client flow=10.1.0.178:36894-10.1.2.143:8083
metric=fct value_ms=16044.672 node=client flow=10.1.0.178:36894-10.1.2.143:8083
metric=send_unlock value_ms=16032.593 node=client flow=10.1.0.178:9512-10.1.2.143:8080
metric=fct value_ms=16044.626 node=client flow=10.1.0.178:9512-10.1.2.143:8080
metric=send_unlock value_ms=16032.578 node=client flow=10.1.0.178:53446-10.1.2.143:8081
metric=fct value_ms=16044.566 node=client flow=10.1.0.178:53446-10.1.2.143:8081
metric=send_unlock value_ms=16032.501 node=client flow=10.1.0.178:3776-10.1.2.143:8082
metric=fct value_ms=16044.541 node=client flow=10.1.0.178:3776-10.1.2.143:8082
metric=send_unlock value_ms=16032.291 node=client flow=10.1.0.178:36904-10.1.2.143:8083
metric=fct value_ms=16044.336 node=client flow=10.1.0.178:36904-10.1.2.143:8083
metric=send_unlock value_ms=16032.395 node=client flow=10.1.0.178:9518-10.1.2.143:8080
metric=fct value_ms=16044.347 node=client flow=10.1.0.178:9518-10.1.2.143:8080
metric=send_unlock value_ms=16032.333 node=client flow=10.1.0.178:53460-10.1.2.143:8081
metric=fct value_ms=16044.290 node=client flow=10.1.0.178:53460-10.1.2.143:8081
metric=send_unlock value_ms=16032.314 node=client flow=10.1.0.178:3786-10.1.2.143:8082
metric=fct value_ms=16048.904 node=client flow=10.1.0.178:3786-10.1.2.143:8082
metric=send_unlock value_ms=16032.270 node=client flow=10.1.0.178:36918-10.1.2.143:8083
metric=fct value_ms=16048.844 node=client flow=10.1.0.178:36918-10.1.2.143:8083
metric=send_unlock value_ms=16032.298 node=client flow=10.1.0.178:9524-10.1.2.143:8080
metric=fct value_ms=16048.846 node=client flow=10.1.0.178:9524-10.1.2.143:8080
metric=send_unlock value_ms=16032.174 node=client flow=10.1.0.178:53474-10.1.2.143:8081
metric=fct value_ms=16048.732 node=client flow=10.1.0.178:53474-10.1.2.143:8081
metric=send_unlock value_ms=16032.193 node=client flow=10.1.0.178:3790-10.1.2.143:8082
metric=fct value_ms=16048.716 node=client flow=10.1.0.178:3790-10.1.2.143:8082
metric=send_unlock value_ms=16032.196 node=client flow=10.1.0.178:36922-10.1.2.143:8083
metric=fct value_ms=16048.662 node=client flow=10.1.0.178:36922-10.1.2.143:8083
metric=send_unlock value_ms=16032.165 node=client flow=10.1.0.178:9538-10.1.2.143:8080
metric=fct value_ms=16048.622 node=client flow=10.1.0.178:9538-10.1.2.143:8080
metric=send_unlock value_ms=16032.135 node=client flow=10.1.0.178:53480-10.1.2.143:8081
metric=fct value_ms=16048.571 node=client flow=10.1.0.178:53480-10.1.2.143:8081
metric=send_unlock value_ms=16032.088 node=client flow=10.1.0.178:3800-10.1.2.143:8082
metric=fct value_ms=16048.510 node=client flow=10.1.0.178:3800-10.1.2.143:8082
metric=send_unlock value_ms=16032.053 node=client flow=10.1.0.178:36928-10.1.2.143:8083
metric=fct value_ms=16048.440 node=client flow=10.1.0.178:36928-10.1.2.143:8083
metric=send_unlock value_ms=16032.030 node=client flow=10.1.0.178:9546-10.1.2.143:8080
metric=fct value_ms=16048.410 node=client flow=10.1.0.178:9546-10.1.2.143:8080
metric=send_unlock value_ms=16032.007 node=client flow=10.1.0.178:53496-10.1.2.143:8081
metric=fct value_ms=16048.345 node=client flow=10.1.0.178:53496-10.1.2.143:8081
metric=send_unlock value_ms=16031.990 node=client flow=10.1.0.178:3812-10.1.2.143:8082
metric=fct value_ms=16048.293 node=client flow=10.1.0.178:3812-10.1.2.143:8082
metric=send_unlock value_ms=16032.087 node=client flow=10.1.0.178:36938-10.1.2.143:8083
metric=fct value_ms=16048.270 node=client flow=10.1.0.178:36938-10.1.2.143:8083
metric=send_unlock value_ms=16031.897 node=client flow=10.1.0.178:9552-10.1.2.143:8080
metric=fct value_ms=16048.179 node=client flow=10.1.0.178:9552-10.1.2.143:8080
metric=send_unlock value_ms=16031.893 node=client flow=10.1.0.178:53504-10.1.2.143:8081
metric=fct value_ms=16048.201 node=client flow=10.1.0.178:53504-10.1.2.143:8081
metric=send_unlock value_ms=16031.867 node=client flow=10.1.0.178:3826-10.1.2.143:8082
metric=fct value_ms=16048.031 node=client flow=10.1.0.178:3826-10.1.2.143:8082
metric=send_unlock value_ms=16031.818 node=client flow=10.1.0.178:36944-10.1.2.143:8083
metric=fct v--output truncated--
metric=server_gap value_ms=16035.528 node=server flow=10.1.0.178:53158-10.1.2.143:8081
metric=server_gap value_ms=16035.560 node=server flow=10.1.0.178:9226-10.1.2.143:8080
metric=server_gap value_ms=16035.586 node=server flow=10.1.0.178:3466-10.1.2.143:8082
metric=server_gap value_ms=16035.558 node=server flow=10.1.0.178:36622-10.1.2.143:8083
metric=server_gap value_ms=16035.506 node=server flow=10.1.0.178:9236-10.1.2.143:8080
metric=server_gap value_ms=16035.480 node=server flow=10.1.0.178:53162-10.1.2.143:8081
metric=server_gap value_ms=16035.385 node=server flow=10.1.0.178:3470-10.1.2.143:8082
metric=server_gap value_ms=16035.398 node=server flow=10.1.0.178:9244-10.1.2.143:8080
metric=server_gap value_ms=16035.321 node=server flow=10.1.0.178:36624-10.1.2.143:8083
metric=server_gap value_ms=16035.355 node=server flow=10.1.0.178:3486-10.1.2.143:8082
metric=server_gap value_ms=16035.325 node=server flow=10.1.0.178:53170-10.1.2.143:8081
metric=server_gap value_ms=16035.322 node=server flow=10.1.0.178:36634-10.1.2.143:8083
metric=server_gap value_ms=16035.293 node=server flow=10.1.0.178:9256-10.1.2.143:8080
metric=server_gap value_ms=16035.254 node=server flow=10.1.0.178:53176-10.1.2.143:8081
metric=server_gap value_ms=16035.191 node=server flow=10.1.0.178:3500-10.1.2.143:8082
metric=server_gap value_ms=16035.164 node=server flow=10.1.0.178:9270-10.1.2.143:8080
metric=server_gap value_ms=16035.045 node=server flow=10.1.0.178:36646-10.1.2.143:8083
metric=server_gap value_ms=16035.182 node=server flow=10.1.0.178:53192-10.1.2.143:8081
metric=server_gap value_ms=16034.954 node=server flow=10.1.0.178:3510-10.1.2.143:8082
metric=server_gap value_ms=16035.096 node=server flow=10.1.0.178:36650-10.1.2.143:8083
metric=server_gap value_ms=16034.957 node=server flow=10.1.0.178:53194-10.1.2.143:8081
metric=server_gap value_ms=16034.944 node=server flow=10.1.0.178:9278-10.1.2.143:8080
metric=server_gap value_ms=16034.948 node=server flow=10.1.0.178:3526-10.1.2.143:8082
metric=server_gap value_ms=16035.010 node=server flow=10.1.0.178:36652-10.1.2.143:8083
metric=server_gap value_ms=16035.009 node=server flow=10.1.0.178:9280-10.1.2.143:8080
metric=server_gap value_ms=16034.844 node=server flow=10.1.0.178:53204-10.1.2.143:8081
metric=server_gap value_ms=16034.906 node=server flow=10.1.0.178:3542-10.1.2.143:8082
metric=server_gap value_ms=16034.906 node=server flow=10.1.0.178:36660-10.1.2.143:8083
metric=server_gap value_ms=16034.991 node=server flow=10.1.0.178:9288-10.1.2.143:8080
metric=server_gap value_ms=16034.797 node=server flow=10.1.0.178:53220-10.1.2.143:8081
metric=server_gap value_ms=16034.985 node=server flow=10.1.0.178:36676-10.1.2.143:8083
metric=server_gap value_ms=16034.592 node=server flow=10.1.0.178:3548-10.1.2.143:8082
metric=server_gap value_ms=16034.885 node=server flow=10.1.0.178:9300-10.1.2.143:8080
metric=server_gap value_ms=16034.844 node=server flow=10.1.0.178:3556-10.1.2.143:8082
metric=server_gap value_ms=16034.726 node=server flow=10.1.0.178:53226-10.1.2.143:8081
metric=server_gap value_ms=16034.717 node=server flow=10.1.0.178:9308-10.1.2.143:8080
metric=server_gap value_ms=16034.692 node=server flow=10.1.0.178:36692-10.1.2.143:8083
metric=server_gap value_ms=16034.585 node=server flow=10.1.0.178:3564-10.1.2.143:8082
metric=server_gap value_ms=16034.524 node=server flow=10.1.0.178:36698-10.1.2.143:8083
metric=server_gap value_ms=16034.427 node=server flow=10.1.0.178:53232-10.1.2.143:8081
metric=server_gap value_ms=16034.443 node=server flow=10.1.0.178:9320-10.1.2.143:8080
metric=server_gap value_ms=16034.463 node=server flow=10.1.0.178:53248-10.1.2.143:8081
metric=server_gap value_ms=16034.330 node=server flow=10.1.0.178:9330-10.1.2.143:8080
metric=server_gap value_ms=16034.264 node=server flow=10.1.0.178:3578-10.1.2.143:8082
metric=server_gap value_ms=16034.335 node=server flow=10.1.0.178:36706-10.1.2.143:8083
metric=server_gap value_ms=16034.530 node=server flow=10.1.0.178:36720-10.1.2.143:8083
metric=server_gap value_ms=16034.150 node=server flow=10.1.0.178:53262-10.1.2.143:8081
metric=server_gap value_ms=16034.389 node=server flow=10.1.0.178:3588-10.1.2.143:8082
metric=server_gap value_ms=16034.505 node=server flow=10.1.0.178:9346-10.1.2.143:8080
metric=server_gap value_ms=16034.440 node=server flow=10.1.0.178:53266-10.1.2.143:8081
metric=server_gap value_ms=16034.361 node=server flow=10.1.0.178:3590-10.1.2.143:8082
metric=server_gap value_ms=16034.361 node=server flow=10.1.0.178:36726-10.1.2.143:8083
metric=server_gap value_ms=16034.276 node=server flow=10.1.0.178:9360-10.1.2.143:8080
metric=server_gap value_ms=16034.327 node=server flow=10.1.0.178:53280-10.1.2.143:8081
metric=server_gap value_ms=16034.224 node=server flow=10.1.0.178:3604-10.1.2.143:8082
metric=server_gap value_ms=16034.081 node=server flow=10.1.0.178:9376-10.1.2.143:8080
metric=server_gap value_ms=16033.957 node=server flow=10.1.0.178:36738-10.1.2.143:8083
metric=server_gap value_ms=16034.022 node=server flow=10.1.0.178:53288-10.1.2.143:8081
metric=server_gap value_ms=16034.009 node=server flow=10.1.0.178:36744-10.1.2.143:8083
metric=server_gap value_ms=16034.031 node=server flow=10.1.0.178:9380-10.1.2.143:8080
metric=server_gap value_ms=16033.861 node=server flow=10.1.0.178:3618-10.1.2.143:8082
metric=server_gap value_ms=16033.983 node=server flow=10.1.0.178:53296-10.1.2.143:8081
metric=server_gap value_ms=16033.854 node=server flow=10.1.0.178:36758-10.1.2.143:8083
metric=server_gap value_ms=16033.674 node=server flow=10.1.0.178:3626-10.1.2.143:8082
metric=server_gap value_ms=16033.820 node=server flow=10.1.0.178:53308-10.1.2.143:8081
metric=server_gap value_ms=16033.748 node=server flow=10.1.0.178:3638-10.1.2.143:8082
metric=server_gap value_ms=16033.811 node=server flow=10.1.0.178:36764-10.1.2.143:8083
metric=server_gap value_ms=16033.633 node=server flow=10.1.0.178:9394-10.1.2.143:8080
metric=server_gap value_ms=16033.794 node=server flow=10.1.0.178:53314-10.1.2.143:8081
metric=server_gap value_ms=16033.746 node=server flow=10.1.0.178:9408-10.1.2.143:8080
metric=server_gap value_ms=16033.746 node=server flow=10.1.0.178:3652-10.1.2.143:8082
metric=server_gap value_ms=16033.649 node=server flow=10.1.0.178:36778-10.1.2.143:8083
metric=server_gap value_ms=16033.613 node=server flow=10.1.0.178:9416-10.1.2.143:8080
metric=server_gap value_ms=16033.459 node=server flow=10.1.0.178:53330-10.1.2.143:8081
metric=server_gap value_ms=16033.578 node=server flow=10.1.0.178:3658-10.1.2.143:8082
metric=server_gap value_ms=16033.449 node=server flow=10.1.0.178:36784-10.1.2.143:8083
metric=server_gap value_ms=16033.497 node=server flow=10.1.0.178:9426-10.1.2.143:8080
metric=server_gap value_ms=16033.522 node=server flow=10.1.0.178:53340-10.1.2.143:8081
metric=server_gap value_ms=16033.505 node=server flow=10.1.0.178:3666-10.1.2.143:8082
metric=server_gap value_ms=16033.472 node=server flow=10.1.0.178:36786-10.1.2.143:8083
metric=server_gap value_ms=16033.477 node=server flow=10.1.0.178:9430-10.1.2.143:8080
metric=server_gap value_ms=16033.425 node=server flow=10.1.0.178:53354-10.1.2.143:8081
metric=server_gap value_ms=16033.356 node=server flow=10.1.0.178:3676-10.1.2.143:8082
metric=server_gap value_ms=16033.372 node=server flow=10.1.0.178:36798-10.1.2.143:8083
metric=server_gap value_ms=16033.341 node=server flow=10.1.0.178:9436-10.1.2.143:8080
metric=server_gap value_ms=16033.346 node=server flow=10.1.0.178:53360-10.1.2.143:8081
metric=server_gap value_ms=16033.242 node=server flow=10.1.0.178:36812-10.1.2.143:8083
metric=server_gap value_ms=16033.324 node=server flow=10.1.0.178:3692-10.1.2.143:8082
metric=server_gap value_ms=16033.240 node=server flow=10.1.0.178:9442-10.1.2.143:8080
metric=server_gap value_ms=16033.258 node=server flow=10.1.0.178:53362-10.1.2.143:8081
metric=server_gap value_ms=16033.256 node=server flow=10.1.0.178:3706-10.1.2.143:8082
metric=server_gap value_ms=16033.100 node=server flow=10.1.0.178:36818-10.1.2.143:8083
metric=server_gap value_ms=16032.931 node=server flow=10.1.0.178:9450-10.1.2.143:8080
metric=server_gap value_ms=16032.977 node=server flow=10.1.0.178:53372-10.1.2.143:8081
metric=server_gap value_ms=16033.025 node=server flow=10.1.0.178:3722-10.1.2.143:8082
metric=server_gap value_ms=16033.016 node=server flow=10.1.0.178:36828-10.1.2.143:8083
metric=server_gap value_ms=16033.069 node=server flow=10.1.0.178:53386-10.1.2.143:8081
metric=server_gap value_ms=16032.941 node=server flow=10.1.0.178:9454-10.1.2.143:8080
metric=server_gap value_ms=16033.043 node=server flow=10.1.0.178:3732-10.1.2.143:8082
metric=server_gap value_ms=16032.768 node=server flow=10.1.0.178:36842-10.1.2.143:8083
metric=server_gap value_ms=16032.915 node=server flow=10.1.0.178:9462-10.1.2.143:8080
metric=server_gap value_ms=16032.996 node=server flow=10.1.0.178:53388-10.1.2.143:8081
metric=server_gap value_ms=16032.948 node=server flow=10.1.0.178:36858-10.1.2.143:8083
metric=server_gap value_ms=16032.870 node=server flow=10.1.0.178:3746-10.1.2.143:8082
metric=server_gap value_ms=16032.714 node=server flow=10.1.0.178:9476-10.1.2.143:8080
metric=server_gap value_ms=16032.760 node=server flow=10.1.0.178:53404-10.1.2.143:8081
metric=server_gap value_ms=16032.844 node=server flow=10.1.0.178:3748-10.1.2.143:8082
metric=server_gap value_ms=16032.710 node=server flow=10.1.0.178:36862-10.1.2.143:8083
metric=server_gap value_ms=16032.726 node=server flow=10.1.0.178:9484-10.1.2.143:8080
metric=server_gap value_ms=16032.716 node=server flow=10.1.0.178:53408-10.1.2.143:8081
metric=server_gap value_ms=16032.677 node=server flow=10.1.0.178:3762-10.1.2.143:8082
metric=server_gap value_ms=16032.669 node=server flow=10.1.0.178:9488-10.1.2.143:8080
metric=server_gap value_ms=16032.584 node=server flow=10.1.0.178:36878-10.1.2.143:8083
metric=server_gap value_ms=16032.569 node=server flow=10.1.0.178:3764-10.1.2.143:8082
metric=server_gap value_ms=16032.625 node=server flow=10.1.0.178:36890-10.1.2.143:8083
metric=server_gap value_ms=16032.541 node=server flow=10.1.0.178:53424-10.1.2.143:8081
metric=server_gap value_ms=16032.657 node=server flow=10.1.0.178:9502-10.1.2.143:8080
metric=server_gap value_ms=16032.503 node=server flow=10.1.0.178:53432-10.1.2.143:8081
metric=server_gap value_ms=16032.585 node=server flow=10.1.0.178:3772-10.1.2.143:8082
metric=server_gap value_ms=16032.533 node=server flow=10.1.0.178:36894-10.1.2.143:8083
metric=server_gap value_ms=16005.440 node=server flow=10.1.0.178:9512-10.1.2.143:8080
metric=server_gap value_ms=16005.493 node=server flow=10.1.0.178:53446-10.1.2.143:8081
metric=server_gap value_ms=16005.586 node=server flow=10.1.0.178:53460-10.1.2.143:8081
metric=server_gap value_ms=16005.364 node=server flow=10.1.0.178:36904-10.1.2.143:8083
metric=server_gap value_ms=16005.766 node=server flow=10.1.0.178:9524-10.1.2.143:8080
metric=server_gap value_ms=16005.813 node=server flow=10.1.0.178:3790-10.1.2.143:8082
metric=server_gap value_ms=16005.627 node=server flow=10.1.0.178:3786-10.1.2.143:8082
metric=server_gap value_ms=16005.483 node=server flow=10.1.0.178:3776-10.1.2.143:8082
metric=server_gap value_ms=16005.656 node=server flow=10.1.0.178:36918-10.1.2.143:8083
metric=server_gap value_ms=16005.706 node=server flow=10.1.0.178:53474-10.1.2.143:8081
metric=server_gap value_ms=16006.249 node=server flow=10.1.0.178:36928-10.1.2.143:8083
metric=server_gap value_ms=16005.493 node=server flow=10.1.0.178:9518-10.1.2.143:8080
metric=server_gap value_ms=16005.959 node=server flow=10.1.0.178:53480-10.1.2.143:8081
metric=server_gap value_ms=16005.989 node=server flow=10.1.0.178:3800-10.1.2.143:8082
metric=server_gap value_ms=16005.895 node=server flow=10.1.0.178:9538-10.1.2.143:8080
metric=server_gap value_ms=16005.824 node=server flow=10.1.0.178:36922-10.1.2.143:8083
metric=server_gap value_ms=16006.142 node=server flow=10.1.0.178:53496-10.1.2.143:8081
metric=server_gap value_ms=16006.268 node=server flow=10.1.0.178:3826-10.1.2.143:8082
metric=server_gap value_ms=16006.109 node=server flow=10.1.0.178:9546-10.1.2.143:8080
metric=server_gap value_ms=16006.605 node=server flow=10.1.0.178:9572-10.1.2.143:8080
metric=server_gap value_ms=16006.334 node=server flow=10.1.0.178:53504-10.1.2.143:8081
metric=server_gap value_ms=16006.331 node=server flow=10.1.0.178:9562-10.1.2.143:8080
metric=server_gap value_ms=16006.289 node=server flow=10.1.0.178:36944-10.1.2.143:8083
metric=server_gap value_ms=16006.672 node=server flow=10.1.0.178:3842-10.1.2.143:8082
metric=server_gap value_ms=16006.461 node=server flow=10.1.0.178:3834-10.1.2.143:8082
metric=server_gap value_ms=16006.545 node=server flow=10.1.0.178:36946-10.1.2.143:8083
metric=server_gap value_ms=16006.102 node=server flow=10.1.0.178:9552-10.1.2.143:8080
metric=server_gap value_ms=16006.103 node=server flow=10.1.0.178:3812-10.1.2.143:8082
metric=server_gap value_ms=16006.358 node=server flow=10.1.0.178:53520-10.1.2.143:8081
metric=server_gap value_ms=16006.137 node=server flow=10.1.0.178:36938-10.1.2.143:8083
metric=server_gap value_ms=16006.701 node=server flow=10.1.0.178:53530-10.1.2.143:8081
metric=server_gap value_ms=16006.764 node=server flow=10.1.0.178:36962-10.1.2.143:8083
metric=server_gap value_ms=16006.905 node=server flow=10.1.0.178:3858-10.1.2.143:8082
metric=server_gap value_ms=16006.711 node=server flow=10.1.0.178:53542-10.1.2.143:8081
metric=server_gap value_ms=16007.041 node=server flow=10.1.0.178:36974-10.1.2.143:8083
metric=server_gap value_ms=16006.880 node=server flow=10.1.0.178:9592-10.1.2.143:8080
metric=server_gap value_ms=16006.943 node=server flow=10.1.0.178:3862-10.1.2.143:8082
metric=server_gap value_ms=16007.102 node=server flow=10.1.0.178:53558-10.1.2.143:8081
metric=server_gap value_ms=16007.137 node=server flow=10.1.0.178:3878-10.1.2.143:8082
metric=server_gap value_ms=16006.718 node=server flow=10.1.0.178:36970-10.1.2.143:8083
metric=server_gap value_ms=16006.797 node=server flow=10.1.0.178:9588-10.1.2.143:8080
metric=server_gap value_ms=16007.168 node=server flow=10.1.0.178:53546-10.1.2.143:8081
metric=server_gap value_ms=16007.053 node=server flow=10.1.0.178:9596-10.1.2.143:8080
metric=server_gap value_ms=16007.202 node=server flow=10.1.0.178:36980-10.1.2.143:8083
metric=server_gap value_ms=16007.411 node=server flow=10.1.0.178:36986-10.1.2.143:8083
metric=server_gap value_ms=16007.360 node=server flow=10.1.0.178:3890-10.1.2.143:8082
metric=server_gap value_ms=16007.263 node=server flow=10.1.0.178:9606-10.1.2.143:8080
metric=server_gap value_ms=16007.307 node=server flow=10.1.0.178:53560-10.1.2.143:8081
metric=server_gap value_ms=16007.084 node=server flow=10.1.0.178:53562-10.1.2.143:8081
metric=server_gap value_ms=16007.057 node=server flow=10.1.0.178:9614-10.1.2.143:8080
metric=server_gap value_ms=16007.360 node=server flow=10.1.0.178:3910-10.1.2.143:8082
metric=server_gap value_ms=16007.574 node=server flow=10.1.0.178:3916-10.1.2.143:8082
metric=server_gap value_ms=16007.535 node=server flow=10.1.0.178:53582-10.1.2.143:8081
metric=server_gap value_ms=16007.283 node=server flow=10.1.0.178:9620-10.1.2.143:8080
metric=server_gap value_ms=16007.709 node=server flow=10.1.0.178:53584-10.1.2.143:8081
metric=server_gap value_ms=16007.406 node=server flow=10.1.0.178:37012-10.1.2.143:8083
metric=server_gap value_ms=16007.668 node=server flow=10.1.0.178:9642-10.1.2.143:8080
metric=server_gap value_ms=16007.192 node=server flow=10.1.0.178:53574-10.1.2.143:8081
metric=server_gap value_ms=16007.050 node=server flow=10.1.0.178:3906-10.1.2.143:8082
metric=server_gap value_ms=16007.115 node=server flow=10.1.0.178:36996-10.1.2.143:8083
metric=server_gap value_ms=16007.425 node=server flow=10.1.0.178:9634-10.1.2.143:8080
metric=server_gap value_ms=16007.807 node=server flow=10.1.0.178:37032-10.1.2.143:8083
metric=server_gap value_ms=16007.734 node=server flow=10.1.0.178:3926-10.1.2.143:8082
metric=server_gap value_ms=16007.531 node=server flow=10.1.0.178:37018-10.1.2.143:8083
metric=server_gap value_ms=16007.544 node=server flow=10.1.0.178:53596-10.1.2.143:8081
metric=server_gap value_ms=16007.431 node=server flow=10.1.0.178:9658-10.1.2.143:8080
metric=server_gap value_ms=16007.483 node=server flow=10.1.0.178:3942-10.1.2.143:8082
metric=server_gap value_ms=16007.565 node=server flow=10.1.0.178:9670-10.1.2.143:8080
metric=server_gap value_ms=16007.748 node=server flow=10.1.0.178:3954-10.1.2.143:8082
metric=server_gap value_ms=16007.717 node=server flow=10.1.0.178:53600-10.1.2.143:8081
metric=server_gap value_ms=16007.954 node=server flow=10.1.0.178:3956-10.1.2.143:8082
metric=server_gap value_ms=16008.088 node=server flow=10.1.0.178:9692-10.1.2.143:8080
metric=server_gap value_ms=16008.014 node=server flow=10.1.0.178:37058-10.1.2.143:8083
metric=server_gap value_ms=16007.731 node=server flow=10.1.0.178:37052-10.1.2.143:8083
metric=server_gap value_ms=16008.179 node=server flow=10.1.0.178:37074-10.1.2.143:8083
metric=server_gap value_ms=16008.250 node=server flow=10.1.0.178:3972-10.1.2.143:8082
metric=server_gap value_ms=16008.124 node=server flow=10.1.0.178:53628-10.1.2.143:8081
metric=server_gap value_ms=16007.823 node=server flow=10.1.0.178:53614-10.1.2.143:8081
metric=server_gap value_ms=16007.553 node=server flow=10.1.0.178:37038-10.1.2.143:8083
metric=server_gap value_ms=16007.753 node=server flow=10.1.0.178:9684-10.1.2.143:8080
metric=server_gap value_ms=15973.711 node=server flow=10.1.0.178:9702-10.1.2.143:8080
metric=server_gap value_ms=15973.726 node=server flow=10.1.0.178:53632-10.1.2.143:8081
metric=server_gap value_ms=15973.862 node=server flow=10.1.0.178:37082-10.1.2.143:8083
metric=server_gap value_ms=15973.976 node=server flow=10.1.0.178:53634-10.1.2.143:8081
metric=server_gap value_ms=15974.058 node=server flow=10.1.0.178:9714-10.1.2.143:8080
metric=server_gap value_ms=15973.936 node=server flow=10.1.0.178:3982-10.1.2.143:8082
metric=server_gap value_ms=15973.889 node=server flow=10.1.0.178:9712-10.1.2.143:8080
metric=server_gap value_ms=15974.140 node=server flow=10.1.0.178:53636-10.1.2.143:8081
metric=server_gap value_ms=15974.171 node=server flow=10.1.0.178:37094-10.1.2.143:8083
metric=server_gap value_ms=15974.271 node=server flow=10.1.0.178:53638-10.1.2.143:8081
metric=server_gap value_ms=15973.667 node=server flow=10.1.0.178:3980-10.1.2.143:8082
metric=server_gap value_ms=15973.938 node=server flow=10.1.0.178:37084-10.1.2.143:8083
metric=server_gap value_ms=15974.135 node=server flow=10.1.0.178:3992-10.1.2.143:8082
metric=server_gap value_ms=15974.308 node=server flow=10.1.0.178:4002-10.1.2.143:8082
metric=server_gap value_ms=15974.184 node=server flow=10.1.0.178:9726-10.1.2.143:8080
metric=server_gap value_ms=15974.304 node=server flow=10.1.0.178:37102-10.1.2.143:8083
metric=server_gap value_ms=15974.188 node=server flow=10.1.0.178:9734-10.1.2.143:8080
metric=server_gap value_ms=15974.337 node=server flow=10.1.0.178:53662-10.1.2.143:8081
metric=server_gap value_ms=15974.506 node=server flow=10.1.0.178:4018-10.1.2.143:8082
metric=server_gap value_ms=15974.528 node=server flow=10.1.0.178:37118-10.1.2.143:8083
metric=server_gap value_ms=15974.761 node=server flow=10.1.0.178:37130-10.1.2.143:8083
metric=server_gap value_ms=15974.740 node=server flow=10.1.0.178:4020-10.1.2.143:8082
metric=server_gap value_ms=15974.802 node=server flow=10.1.0.178:9770-10.1.2.143:8080
metric=server_gap value_ms=15974.572 node=server flow=10.1.0.178:9754-10.1.2.143:8080
metric=server_gap value_ms=15974.246 node=server flow=10.1.0.178:4012-10.1.2.143:8082
metric=server_gap value_ms=15974.342 node=server flow=10.1.0.178:37108-10.1.2.143:8083
metric=server_gap value_ms=15974.423 node=server flow=10.1.0.178:9740-10.1.2.143:8080
metric=server_gap value_ms=15974.216 node=server flow=10.1.0.178:53650-10.1.2.143:8081
metric=server_gap value_ms=15974.645 node=server flow=10.1.0.178:53670-10.1.2.143:8081
metric=server_gap value_ms=15974.822 node=server flow=10.1.0.178:53686-10.1.2.143:8081
metric=server_gap value_ms=15974.946 node=server flow=10.1.0.178:4032-10.1.2.143:8082
metric=server_gap value_ms=15974.776 node=server flow=10.1.0.178:37136-10.1.2.143:8083
metric=server_gap value_ms=15975.171 node=server flow=10.1.0.178:4046-10.1.2.143:8082
metric=server_gap value_ms=15975.069 node=server flow=10.1.0.178:9798-10.1.2.143:8080
metric=server_gap value_ms=15975.212 node=server flow=10.1.0.178:37154-10.1.2.143:8083
metric=server_gap value_ms=15975.105 node=server flow=10.1.0.178:53698-10.1.2.143:8081
metric=server_gap value_ms=15975.585 node=server flow=10.1.0.178:37178-10.1.2.143:8083
metric=server_gap value_ms=15975.465 node=server flow=10.1.0.178:9822-10.1.2.143:8080
metric=server_gap value_ms=15974.975 node=server flow=10.1.0.178:37146-10.1.2.143:8083
metric=server_gap value_ms=15975.362 node=server flow=10.1.0.178:4062-10.1.2.143:8082
metric=server_gap value_ms=15974.916 node=server flow=10.1.0.178:53694-10.1.2.143:8081
metric=server_gap value_ms=15975.282 node=server flow=10.1.0.178:9810-10.1.2.143:8080
metric=server_gap value_ms=15974.787 node=server flow=10.1.0.178:9786-10.1.2.143:8080
metric=server_gap value_ms=15974.907 node=server flow=10.1.0.178:4042-10.1.2.143:8082
metric=server_gap value_ms=15975.285 node=server flow=10.1.0.178:53710-10.1.2.143:8081
metric=server_gap value_ms=15975.368 node=server flow=10.1.0.178:37166-10.1.2.143:8083
metric=server_gap value_ms=15975.504 node=server flow=10.1.0.178:4068-10.1.2.143:8082
metric=server_gap value_ms=15975.450 node=server flow=10.1.0.178:53724-10.1.2.143:8081
metric=server_gap value_ms=15975.678 node=server flow=10.1.0.178:4082-10.1.2.143:8082
metric=server_gap value_ms=15975.433 node=server flow=10.1.0.178:9838-10.1.2.143:8080
metric=server_gap value_ms=15975.576 node=server flow=10.1.0.178:37186-10.1.2.143:8083
metric=server_gap value_ms=15975.539 node=server flow=10.1.0.178:53726-10.1.2.143:8081
metric=server_gap value_ms=15976.244 node=server flow=10.1.0.178:37198-10.1.2.143:8083
metric=server_gap value_ms=15976.088 node=server flow=10.1.0.178:4094-10.1.2.143:8082
metric=server_gap value_ms=15976.411 node=server flow=10.1.0.178:4110-10.1.2.143:8082
metric=server_gap value_ms=15975.771 node=server flow=10.1.0.178:53730-10.1.2.143:8081
metric=server_gap value_ms=15976.018 node=server flow=10.1.0.178:53732-10.1.2.143:8081
metric=server_gap value_ms=15975.969 node=server flow=10.1.0.178:9858-10.1.2.143:8080
metric=server_gap value_ms=15976.346 node=server flow=10.1.0.178:37212-10.1.2.143:8083
metric=server_gap value_ms=15976.269 node=server flow=10.1.0.178:53744-10.1.2.143:8081
metric=server_gap value_ms=15976.151 node=server flow=10.1.0.178:9870-10.1.2.143:8080
metric=server_gap value_ms=15975.625 node=server flow=10.1.0.178:9848-10.1.2.143:8080
metric=server_gap value_ms=15975.844 node=server flow=10.1.0.178:37190-10.1.2.143:8083
metric=server_gap value_ms=15975.774 node=server flow=10.1.0.178:4088-10.1.2.143:8082
metric=server_gap value_ms=15976.334 node=server flow=10.1.0.178:53748-10.1.2.143:8081
metric=server_gap value_ms=15976.450 node=server flow=10.1.0.178:9888-10.1.2.143:8080
metric=server_gap value_ms=15976.518 node=server flow=10.1.0.178:9894-10.1.2.143:8080
metric=server_gap value_ms=15976.474 node=server flow=10.1.0.178:53750-10.1.2.143:8081
metric=server_gap value_ms=15976.776 node=server flow=10.1.0.178:53766-10.1.2.143:8081
metric=server_gap value_ms=15976.177 node=server flow=10.1.0.178:9884-10.1.2.143:8080
metric=server_gap value_ms=15976.318 node=server flow=10.1.0.178:4116-10.1.2.143:8082
metric=server_gap value_ms=15976.812 node=server flow=10.1.0.178:4136-10.1.2.143:8082
metric=server_gap value_ms=15976.366 node=server flow=10.1.0.178:37228-10.1.2.143:8083
metric=server_gap value_ms=15976.809 node=server flow=10.1.0.178:37250-10.1.2.143:8083
metric=server_gap value_ms=15976.939 node=server flow=10.1.0.178:37256-10.1.2.143:8083
metric=server_gap value_ms=15976.653 node=server flow=10.1.0.178:4126-10.1.2.143:8082
metric=server_gap value_ms=15976.743 node=server flow=10.1.0.178:37234-10.1.2.143:8083
metric=server_gap v--output truncated--
```
