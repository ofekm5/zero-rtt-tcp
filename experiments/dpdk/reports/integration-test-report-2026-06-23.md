# Integration Test Report — 2026-06-23

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: ALL PASSED

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : n=100  min=5330.338  mean=13539.515  median=9596.882  max=38534.017 ms
  Send unlock   : n=100  min=0.267  mean=12.571  median=10.336  max=30.055 ms
  Server gap    : n=100  min=1.641  mean=165.220  median=213.419  max=238.301 ms
```

## Client Output

```
--- Round 1/1: 4 port(s) [8080-8083] x 25 parallel = 100 conns ---
------------------------------------------------------------
Client connecting to 10.1.2.231, TCP port 8080
TCP window size: 0.04 MByte (default)
------------------------------------------------------------
[ 27] local 10.1.0.16 port 50140 connected with 10.1.2.231 port 8080
[  5] local 10.1.0.16 port 49944 connected with 10.1.2.231 port 8080
[  7] local 10.1.0.16 port 49956 connected with 10.1.2.231 port 8080
[  9] local 10.1.0.16 port 49974 connected with 10.1.2.231 port 8080
[ 13] local 10.1.0.16 port 50002 connected with 10.1.2.231 port 8080
[ 11] local 10.1.0.16 port 49990 connected with 10.1.2.231 port 8080
[ 15] local 10.1.0.16 port 50022 connected with 10.1.2.231 port 8080
[ 17] local 10.1.0.16 port 50036 connected with 10.1.2.231 port 8080
[ 19] local 10.1.0.16 port 50066 connected with 10.1.2.231 port 8080
[ 21] local 10.1.0.16 port 50080 connected with 10.1.2.231 port 8080
[  3] local 10.1.0.16 port 49916 connected with 10.1.2.231 port 8080
[  4] local 10.1.0.16 port 49930 connected with 10.1.2.231 port 8080
[ 23] local 10.1.0.16 port 50092 connected with 10.1.2.231 port 8080
[ 26] local 10.1.0.16 port 50124 connected with 10.1.2.231 port 8080
[  6] local 10.1.0.16 port 49948 connected with 10.1.2.231 port 8080
[  8] local 10.1.0.16 port 49958 connected with 10.1.2.231 port 8080
[ 25] local 10.1.0.16 port 50110 connected with 10.1.2.231 port 8080
[ 10] local 10.1.0.16 port 49976 connected with 10.1.2.231 port 8080
[ 12] local 10.1.0.16 port 49998 connected with 10.1.2.231 port 8080
[ 14] local 10.1.0.16 port 50010 connected with 10.1.2.231 port 8080
[ 16] local 10.1.0.16 port 50032 connected with 10.1.2.231 port 8080
[ 18] local 10.1.0.16 port 50050 connected with 10.1.2.231 port 8080
[ 20] local 10.1.0.16 port 50070 connected with 10.1.2.231 port 8080
[ 24] local 10.1.0.16 port 50094 connected with 10.1.2.231 port 8080
[ 22] local 10.1.0.16 port 50082 connected with 10.1.2.231 port 8080
[ ID] Interval       Transfer     Bandwidth
[  6]  0.0- 5.2 sec  1.00 MBytes  1.62 Mbits/sec
[ 27]  0.0- 5.9 sec  1.00 MBytes  1.43 Mbits/sec
[ 21]  0.0- 6.1 sec  1.00 MBytes  1.37 Mbits/sec
[ 19]  0.0- 6.4 sec  1.00 MBytes  1.32 Mbits/sec
[ 10]  0.0- 6.4 sec  1.00 MBytes  1.31 Mbits/sec
[ 26]  0.0- 6.4 sec  1.00 MBytes  1.31 Mbits/sec
[ 20]  0.0- 6.4 sec  1.00 MBytes  1.30 Mbits/sec
[ 16]  0.0- 6.6 sec  1.00 MBytes  1.27 Mbits/sec
[  4]  0.0- 6.7 sec  1.00 MBytes  1.25 Mbits/sec
[  9]  0.0- 6.8 sec  1.00 MBytes  1.24 Mbits/sec
[ 13]  0.0- 6.8 sec  1.00 MBytes  1.24 Mbits/sec
[  7]  0.0- 6.8 sec  1.00 MBytes  1.23 Mbits/sec
[ 15]  0.0- 7.0 sec  1.00 MBytes  1.21 Mbits/sec
[ 23]  0.0- 7.0 sec  1.00 MBytes  1.19 Mbits/sec
[  5]  0.0- 7.5 sec  1.00 MBytes  1.12 Mbits/sec
[ 24]  0.0- 7.6 sec  1.00 MBytes  1.10 Mbits/sec
[ 18]  0.0- 8.8 sec  1.00 MBytes  0.96 Mbits/sec
[ 22]  0.0- 8.9 sec  1.00 MBytes  0.95 Mbits/sec
[  3]  0.0- 9.8 sec  1.00 MBytes  0.86 Mbits/sec
[ 14]  0.0- 9.9 sec  1.00 MBytes  0.85 Mbits/sec
[  8]  0.0-10.7 sec  1.00 MBytes  0.79 Mbits/sec
[ 17]  0.0-15.6 sec  1.00 MBytes  0.54 Mbits/sec
[ 25]  0.0-24.1 sec  1.00 MBytes  0.35 Mbits/sec
[ 12]  0.0-31.5 sec  1.00 MBytes  0.27 Mbits/sec
[ 11]  0.0-34.7 sec  1.00 MBytes  0.24 Mbits/sec
[SUM]  0.0-34.7 sec  25.0 MBytes  6.04 Mbits/sec
------------------------------------------------------------
Client connecting to 10.1.2.231, TCP port 8081
TCP window size: 0.04 MByte (default)
------------------------------------------------------------
[ 19] local 10.1.0.16 port 56674 connected with 10.1.2.231 port 8081
[ 21] local 10.1.0.16 port 56688 connected with 10.1.2.231 port 8081
[ 27] local 10.1.0.16 port 56746 connected with 10.1.2.231 port 8081
[ 22] local 10.1.0.16 port 56694 connected with 10.1.2.231 port 8081
[ 25] local 10.1.0.16 port 56728 connected with 10.1.2.231 port 8081
[  4] local 10.1.0.16 port 56536 connected with 10.1.2.231 port 8081
[  5] local 10.1.0.16 port 56540 connected with 10.1.2.231 port 8081
[  7] local 10.1.0.16 port 56568 connected with 10.1.2.231 port 8081
[  3] local 10.1.0.16 port 56520 connected with 10.1.2.231 port 8081
[  9] local 10.1.0.16 port 56596 connected with 10.1.2.231 port 8081
[  6] local 10.1.0.16 port 56554 connected with 10.1.2.231 port 8081
[ 11] local 10.1.0.16 port 56604 connected with 10.1.2.231 port 8081
[  8] local 10.1.0.16 port 56582 connected with 10.1.2.231 port 8081
[ 15] local 10.1.0.16 port 56632 connected with 10.1.2.231 port 8081
[ 10] local 10.1.0.16 port 56600 connected with 10.1.2.231 port 8081
[ 20] local 10.1.0.16 port 56678 connected with 10.1.2.231 port 8081
[ 12] local 10.1.0.16 port 56616 connected with 10.1.2.231 port 8081
[ 24] local 10.1.0.16 port 56712 connected with 10.1.2.231 port 8081
[ 23] local 10.1.0.16 port 56702 connected with 10.1.2.231 port 8081
[ 17] local 10.1.0.16 port 56658 connected with 10.1.2.231 port 8081
[ 18] local 10.1.0.16 port 56662 connected with 10.1.2.231 port 8081
[ 14] local 10.1.0.16 port 56626 connected with 10.1.2.231 port 8081
[ 26] local 10.1.0.16 port 56740 connected with 10.1.2.231 port 8081
[ 16] local 10.1.0.16 port 56648 connected with 10.1.2.231 port 8081
[ 13] local 10.1.0.16 port 56618 connected with 10.1.2.231 port 8081
[ ID] Interval       Transfer     Bandwidth
[  7]  0.0- 5.9 sec  1.00 MBytes  1.41 Mbits/sec
[ 18]  0.0- 6.0 sec  1.00 MBytes  1.39 Mbits/sec
[  3]  0.0- 6.1 sec  1.00 MBytes  1.38 Mbits/sec
[  6]  0.0- 6.2 sec  1.00 MBytes  1.36 Mbits/sec
[  9]  0.0- 6.2 sec  1.00 MBytes  1.34 Mbits/sec
[ 19]  0.0- 6.4 sec  1.00 MBytes  1.30 Mbits/sec
[ 11]  0.0- 6.5 sec  1.00 MBytes  1.30 Mbits/sec
[ 24]  0.0- 6.5 sec  1.00 MBytes  1.29 Mbits/sec
[ 21]  0.0- 6.6 sec  1.00 MBytes  1.27 Mbits/sec
[ 27]  0.0- 7.0 sec  1.00 MBytes  1.20 Mbits/sec
[ 22]  0.0- 7.0 sec  1.00 MBytes  1.20 Mbits/sec
[ 26]  0.0- 7.0 sec  1.00 MBytes  1.19 Mbits/sec
[ 10]  0.0- 7.5 sec  1.00 MBytes  1.12 Mbits/sec
[ 14]  0.0- 7.5 sec  1.00 MBytes  1.11 Mbits/sec
[ 13]  0.0- 7.9 sec  1.00 MBytes  1.06 Mbits/sec
[ 20]  0.0- 9.0 sec  1.00 MBytes  0.93 Mbits/sec
[ 12]  0.0- 9.2 sec  1.00 MBytes  0.91 Mbits/sec
[  5]  0.0- 9.7 sec  1.00 MBytes  0.86 Mbits/sec
[ 23]  0.0-12.2 sec  1.00 MBytes  0.69 Mbits/sec
[ 25]  0.0-19.1 sec  1.00 MBytes  0.44 Mbits/sec
[  4]  0.0-21.5 sec  1.00 MBytes  0.39 Mbits/sec
[ 16]  0.0-23.7 sec  1.00 MBytes  0.35 Mbits/sec
[ 17]  0.0-26.6 sec  1.00 MBytes  0.32 Mbits/sec
[ 15]  0.0-33.4 sec  1.00 MBytes  0.25 Mbits/sec
[  8]  0.0-33.6 sec  1.00 MBytes  0.25 Mbits/sec
[SUM]  0.0-33.6 sec  25.0 MBytes  6.25 Mbits/sec
------------------------------------------------------------
Client connecting to 10.1.2.231, TCP port 8082
TCP window size: 0.04 MByte (default)
------------------------------------------------------------
[ 27] local 10.1.0.16 port 38320 connected with 10.1.2.231 port 8082
[ 20] local 10.1.0.16 port 38248 connected with 10.1.2.231 port 8082
[  4] local 10.1.0.16 port 38108 connected with 10.1.2.231 port 8082
[  7] local 10.1.0.16 port 38142 connected with 10.1.2.231 port 8082
[  5] local 10.1.0.16 port 38124 connected with 10.1.2.231 port 8082
[  6] local 10.1.0.16 port 38126 connected with 10.1.2.231 port 8082
[  8] local 10.1.0.16 port 38152 connected with 10.1.2.231 port 8082
[  9] local 10.1.0.16 port 38158 connected with 10.1.2.231 port 8082
[ 16] local 10.1.0.16 port 38222 connected with 10.1.2.231 port 8082
[ 14] local 10.1.0.16 port 38204 connected with 10.1.2.231 port 8082
[ 21] local 10.1.0.16 port 38258 connected with 10.1.2.231 port 8082
[ 19] local 10.1.0.16 port 38246 connected with 10.1.2.231 port 8082
[  3] local 10.1.0.16 port 38098 connected with 10.1.2.231 port 8082
[ 23] local 10.1.0.16 port 38280 connected with 10.1.2.231 port 8082
[ 24] local 10.1.0.16 port 38286 connected with 10.1.2.231 port 8082
[ 17] local 10.1.0.16 port 38228 connected with 10.1.2.231 port 8082
[ 10] local 10.1.0.16 port 38166 connected with 10.1.2.231 port 8082
[ 18] local 10.1.0.16 port 38242 connected with 10.1.2.231 port 8082
[ 13] local 10.1.0.16 port 38198 connected with 10.1.2.231 port 8082
[ 25] local 10.1.0.16 port 38300 connected with 10.1.2.231 port 8082
[ 11] local 10.1.0.16 port 38172 connected with 10.1.2.231 port 8082
[ 26] local 10.1.0.16 port 38314 connected with 10.1.2.231 port 8082
[ 15] local 10.1.0.16 port 38218 connected with 10.1.2.231 port 8082
[ 22] local 10.1.0.16 port 38266 connected with 10.1.2.231 port 8082
[ 12] local 10.1.0.16 port 38182 connected with 10.1.2.231 port 8082
[ ID] Interval       Transfer     Bandwidth
[ 10]  0.0- 5.4 sec  1.00 MBytes  1.55 Mbits/sec
[ 27]  0.0- 6.4 sec  1.00 MBytes  1.32 Mbits/sec
[ 14]  0.0- 6.4 sec  1.00 MBytes  1.31 Mbits/sec
[ 23]  0.0- 6.4 sec  1.00 MBytes  1.32 Mbits/sec
[ 11]  0.0- 6.4 sec  1.00 MBytes  1.30 Mbits/sec
[ 22]  0.0- 6.5 sec  1.00 MBytes  1.30 Mbits/sec
[ 24]  0.0- 6.6 sec  1.00 MBytes  1.27 Mbits/sec
[ 16]  0.0- 6.7 sec  1.00 MBytes  1.24 Mbits/sec
[ 20]  0.0- 7.0 sec  1.00 MBytes  1.19 Mbits/sec
[  6]  0.0- 7.5 sec  1.00 MBytes  1.12 Mbits/sec
[  5]  0.0- 7.7 sec  1.00 MBytes  1.09 Mbits/sec
[  4]  0.0- 8.3 sec  1.00 MBytes  1.01 Mbits/sec
[ 19]  0.0- 8.9 sec  1.00 MBytes  0.94 Mbits/sec
[ 25]  0.0- 9.1 sec  1.00 MBytes  0.92 Mbits/sec
[  8]  0.0- 9.6 sec  1.00 MBytes  0.88 Mbits/sec
[ 13]  0.0- 9.9 sec  1.00 MBytes  0.85 Mbits/sec
[ 26]  0.0-11.6 sec  1.00 MBytes  0.72 Mbits/sec
[ 12]  0.0-12.8 sec  1.00 MBytes  0.66 Mbits/sec
[  9]  0.0-13.6 sec  1.00 MBytes  0.62 Mbits/sec
[ 21]  0.0-14.9 sec  1.00 MBytes  0.56 Mbits/sec
[ 17]  0.0-18.6 sec  1.00 MBytes  0.45 Mbits/sec
[  3]  0.0-19.1 sec  1.00 MBytes  0.44 Mbits/sec
[ 15]  0.0-19.8 sec  1.00 MBytes  0.42 Mbits/sec
[  7]  0.0-21.8 sec  1.00 MBytes  0.38 Mbits/sec
[ 18]  0.0-31.1 sec  1.00 MBytes  0.27 Mbits/sec
[SUM]  0.0-31.1 sec  25.0 MBytes  6.75 Mbits/sec
------------------------------------------------------------
Client connecting to 10.1.2.231, TCP port 8083
TCP window size: 0.04 MByte (default)
------------------------------------------------------------
[ 26] local 10.1.0.16 port 47992 connected with 10.1.2.231 port 8083
[ 22] local 10.1.0.16 port 47974 connected with 10.1.2.231 port 8083
[ 20] local 10.1.0.16 port 47950 connected with 10.1.2.231 port 8083
[ 12] local 10.1.0.16 port 47872 connected with 10.1.2.231 port 8083
[ 10] local 10.1.0.16 port 47840 connected with 10.1.2.231 port 8083
[  5] local 10.1.0.16 port 47788 connected with 10.1.2.231 port 8083
[  7] local 10.1.0.16 port 47808 connected with 10.1.2.231 port 8083
[ 21] local 10.1.0.16 port 47962 connected with 10.1.2.231 port 8083
[ 18] local 10.1.0.16 port 47934 connected with 10.1.2.231 port 8083
[  6] local 10.1.0.16 port 47796 connected with 10.1.2.231 port 8083
[ 13] local 10.1.0.16 port 47880 connected with 10.1.2.231 port 8083
[ 23] local 10.1.0.16 port 47980 connected with 10.1.2.231 port 8083
[  9] local 10.1.0.16 port 47828 connected with 10.1.2.231 port 8083
[  3] local 10.1.0.16 port 47766 connected with 10.1.2.231 port 8083
[ 24] local 10.1.0.16 port 47982 connected with 10.1.2.231 port 8083
[ 25] local 10.1.0.16 port 47984 connected with 10.1.2.231 port 8083
[ 27] local 10.1.0.16 port 48004 connected with 10.1.2.231 port 8083
[ 11] local 10.1.0.16 port 47856 connected with 10.1.2.231 port 8083
[ 16] local 10.1.0.16 port 47912 connected with 10.1.2.231 port 8083
[  4] local 10.1.0.16 port 47778 connected with 10.1.2.231 port 8083
[ 14] local 10.1.0.16 port 47886 connected with 10.1.2.231 port 8083
[  8] local 10.1.0.16 port 47816 connected with 10.1.2.231 port 8083
[ 15] local 10.1.0.16 port 47898 connected with 10.1.2.231 port 8083
[ 19] local 10.1.0.16 port 47936 connected with 10.1.2.231 port 8083
[ 17] local 10.1.0.16 port 47920 connected with 10.1.2.231 port 8083
[ ID] Interval       Transfer     Bandwidth
[ 22]  0.0- 5.6 sec  1.00 MBytes  1.50 Mbits/sec
[  4]  0.0- 6.1 sec  1.00 MBytes  1.37 Mbits/sec
[ 10]  0.0- 6.3 sec  1.00 MBytes  1.33 Mbits/sec
[ 24]  0.0- 6.4 sec  1.00 MBytes  1.30 Mbits/sec
[ 25]  0.0- 6.5 sec  1.00 MBytes  1.30 Mbits/sec
[ 23]  0.0- 7.3 sec  1.00 MBytes  1.15 Mbits/sec
[ 19]  0.0- 7.8 sec  1.00 MBytes  1.08 Mbits/sec
[  8]  0.0- 7.9 sec  1.00 MBytes  1.06 Mbits/sec
[ 12]  0.0- 8.3 sec  1.00 MBytes  1.01 Mbits/sec
[ 14]  0.0- 8.6 sec  1.00 MBytes  0.98 Mbits/sec
[  9]  0.0- 8.9 sec  1.00 MBytes  0.95 Mbits/sec
[ 18]  0.0- 9.2 sec  1.00 MBytes  0.91 Mbits/sec
[  5]  0.0- 9.4 sec  1.00 MBytes  0.89 Mbits/sec
[ 16]  0.0-10.4 sec  1.00 MBytes  0.81 Mbits/sec
[ 27]  0.0-10.7 sec  1.00 MBytes  0.78 Mbits/sec
[ 20]  0.0-12.0 sec  1.00 MBytes  0.70 Mbits/sec
[ 21]  0.0-12.4 sec  1.00 MBytes  0.67 Mbits/sec
[  6]  0.0-13.1 sec  1.00 MBytes  0.64 Mbits/sec
[ 17]  0.0-13.8 sec  1.00 MBytes  0.61 Mbits/sec
[ 26]  0.0-18.7 sec  1.00 MBytes  0.45 Mbits/sec
[  7]  0.0-19.4 sec  1.00 MBytes  0.43 Mbits/sec
[ 15]  0.0-32.5 sec  1.00 MBytes  0.26 Mbits/sec
[  3]  0.0-32.7 sec  1.00 MBytes  0.26 Mbits/sec
[ 11]  0.0-34.8 sec  1.00 MBytes  0.24 Mbits/sec
[ 13]  0.0-36.6 sec  1.00 MBytes  0.23 Mbits/sec
[SUM]  0.0-36.6 sec  25.0 MBytes  5.73 Mbits/sec
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x01dfec1d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xcc02fddc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2cc26982 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb3179916 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xab2dc86c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6f58e7b3 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7fa2e8ba in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe80c4593 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe8905887 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd2019207 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x02e1eb14 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3a8d462d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6447138e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5e8f69b8 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x44c4c388 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x27d18b09 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x89c87108 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe615fce7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x6acd6563 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x767255e7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe12f2801 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0d3ec7ca in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x40dee4b2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x4df3a33f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x46d6609a in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x472ec6a7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1c715205 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7e103204 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd26f6697 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb92e2af2 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xb80500a0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa35f28a7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x2e17731f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x88078178 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x04b22cd6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xc6f66c84 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9504e718 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9f1bc3e6 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x295ba0a4 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x392d82cc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xbe7307e0 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x790fe17d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3f29f183 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xab7dd8c1 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa95ed805 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x566f27ba in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0b465efe in ack-num
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
SERVERNIC: SYN: new flow, V=0x295ba0a4
SERVERNIC: SYN-ACK: delta=0x33241eec, V=0x9f1bc3e6, real_isn=0x6bf7a4fa
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xe9df65bf, V=0x295ba0a4, real_isn=0x3f7c3ae5
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x392d82cc
SERVERNIC: SYN-ACK: delta=0x35433808, V=0x392d82cc, real_isn=0x03ea4ac4
SERVERNIC: SYN: new flow, V=0xbe7307e0
SERVERNIC: SYN-ACK: delta=0x2e7882c3, V=0xbe7307e0, real_isn=0x8ffa851d
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0x790fe17d
SERVERNIC: SYN: new flow, V=0x3f29f183
SERVERNIC: SYN-ACK: delta=0x2bb42235, V=0x790fe17d, real_isn=0x4d5bbf48
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xfa56dbc6, V=0x3f29f183, real_isn=0x44d315bd
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xab7dd8c1
SERVERNIC: SYN-ACK: delta=0xe95cadc3, V=0xab7dd8c1, real_isn=0xc2212afe
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN: new flow, V=0xa95ed805
SERVERNIC: SYN: new flow, V=0x566f27ba
SERVERNIC: SYN-ACK: delta=0xdc32fd55, V=0xa95ed805, real_isn=0xcd2bdab0
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: SYN-ACK: delta=0xa32b1d97, V=0x566f27ba, real_isn=0xb3440a23
SERVERNIC: SYN: new flow, V=0x0b465efe
SERVERNIC: SYN-ACK: delta=0x095a9315, V=0x0b465efe, real_isn=0x01ebcbe9
SERVERNIC: SYN-ACK: flushed 1 buffered c2s packets
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## Server Log

```
[  5]  0.0-22.8 sec  1.00 MBytes   368 Kbits/sec
[  8]  0.0-22.9 sec  1.00 MBytes   366 Kbits/sec
[  8]  0.0-24.8 sec  1.00 MBytes   338 Kbits/sec
[  9]  0.0-25.1 sec  1.00 MBytes   334 Kbits/sec
[ 27]  0.0-26.1 sec  1.00 MBytes   322 Kbits/sec
[ 18]  0.0-27.0 sec  1.00 MBytes   311 Kbits/sec
[ 17]  0.0-27.6 sec  1.00 MBytes   303 Kbits/sec
[ 19]  0.0-32.2 sec  1.00 MBytes   260 Kbits/sec
[SUM]  0.0-32.2 sec  25.0 MBytes  6.51 Mbits/sec
[ 14]  0.0-32.5 sec  1.00 MBytes   258 Kbits/sec
[  4]  0.0-33.6 sec  1.00 MBytes   250 Kbits/sec
[ 16]  0.0-34.4 sec  1.00 MBytes   244 Kbits/sec
[ 16]  0.0-34.4 sec  1.00 MBytes   244 Kbits/sec
[ 10]  0.0-35.1 sec  1.00 MBytes   239 Kbits/sec
[SUM]  0.0-35.1 sec  25.0 MBytes  5.98 Mbits/sec
[ 11]  0.0-35.7 sec  1.00 MBytes   235 Kbits/sec
[SUM]  0.0-35.7 sec  25.0 MBytes  5.87 Mbits/sec
[ 12]  0.0-36.1 sec  1.00 MBytes   232 Kbits/sec
[ 14]  0.0-38.3 sec  1.00 MBytes   219 Kbits/sec
[SUM]  0.0-38.3 sec  25.0 MBytes  5.47 Mbits/sec
```

## Packet Analysis

```
metric=send_unlock value_ms=9.877 node=client flow=10.1.0.16:49916-10.1.2.231:8080
metric=fct value_ms=12106.769 node=client flow=10.1.0.16:49916-10.1.2.231:8080
metric=send_unlock value_ms=9.207 node=client flow=10.1.0.16:49930-10.1.2.231:8080
metric=fct value_ms=6813.086 node=client flow=10.1.0.16:49930-10.1.2.231:8080
metric=send_unlock value_ms=7.980 node=client flow=10.1.0.16:49944-10.1.2.231:8080
metric=fct value_ms=7780.833 node=client flow=10.1.0.16:49944-10.1.2.231:8080
metric=send_unlock value_ms=8.639 node=client flow=10.1.0.16:49948-10.1.2.231:8080
metric=fct value_ms=5330.338 node=client flow=10.1.0.16:49948-10.1.2.231:8080
metric=send_unlock value_ms=7.366 node=client flow=10.1.0.16:49956-10.1.2.231:8080
metric=fct value_ms=7733.685 node=client flow=10.1.0.16:49956-10.1.2.231:8080
metric=send_unlock value_ms=8.243 node=client flow=10.1.0.16:49958-10.1.2.231:8080
metric=fct value_ms=25323.694 node=client flow=10.1.0.16:49958-10.1.2.231:8080
metric=send_unlock value_ms=6.758 node=client flow=10.1.0.16:49974-10.1.2.231:8080
metric=fct value_ms=7068.677 node=client flow=10.1.0.16:49974-10.1.2.231:8080
metric=send_unlock value_ms=7.596 node=client flow=10.1.0.16:49976-10.1.2.231:8080
metric=fct value_ms=6520.833 node=client flow=10.1.0.16:49976-10.1.2.231:8080
metric=send_unlock value_ms=6.158 node=client flow=10.1.0.16:49990-10.1.2.231:8080
metric=fct value_ms=35918.188 node=client flow=10.1.0.16:49990-10.1.2.231:8080
metric=send_unlock value_ms=6.943 node=client flow=10.1.0.16:49998-10.1.2.231:8080
metric=fct value_ms=32685.204 node=client flow=10.1.0.16:49998-10.1.2.231:8080
metric=send_unlock value_ms=5.409 node=client flow=10.1.0.16:50002-10.1.2.231:8080
metric=fct value_ms=8369.468 node=client flow=10.1.0.16:50002-10.1.2.231:8080
metric=send_unlock value_ms=6.297 node=client flow=10.1.0.16:50010-10.1.2.231:8080
metric=fct value_ms=22671.895 node=client flow=10.1.0.16:50010-10.1.2.231:8080
metric=send_unlock value_ms=4.871 node=client flow=10.1.0.16:50022-10.1.2.231:8080
metric=fct value_ms=7067.319 node=client flow=10.1.0.16:50022-10.1.2.231:8080
metric=send_unlock value_ms=5.657 node=client flow=10.1.0.16:50032-10.1.2.231:8080
metric=fct value_ms=6745.388 node=client flow=10.1.0.16:50032-10.1.2.231:8080
metric=send_unlock value_ms=4.255 node=client flow=10.1.0.16:50036-10.1.2.231:8080
metric=fct value_ms=18383.728 node=client flow=10.1.0.16:50036-10.1.2.231:8080
metric=send_unlock value_ms=5.041 node=client flow=10.1.0.16:50050-10.1.2.231:8080
metric=fct value_ms=9489.509 node=client flow=10.1.0.16:50050-10.1.2.231:8080
metric=send_unlock value_ms=3.679 node=client flow=10.1.0.16:50066-10.1.2.231:8080
metric=fct value_ms=6761.304 node=client flow=10.1.0.16:50066-10.1.2.231:8080
metric=send_unlock value_ms=4.435 node=client flow=10.1.0.16:50070-10.1.2.231:8080
metric=fct value_ms=6782.721 node=client flow=10.1.0.16:50070-10.1.2.231:8080
metric=send_unlock value_ms=3.118 node=client flow=10.1.0.16:50080-10.1.2.231:8080
metric=fct value_ms=7835.699 node=client flow=10.1.0.16:50080-10.1.2.231:8080
metric=send_unlock value_ms=3.896 node=client flow=10.1.0.16:50082-10.1.2.231:8080
metric=fct value_ms=9548.716 node=client flow=10.1.0.16:50082-10.1.2.231:8080
metric=send_unlock value_ms=2.592 node=client flow=10.1.0.16:50092-10.1.2.231:8080
metric=fct value_ms=7353.227 node=client flow=10.1.0.16:50092-10.1.2.231:8080
metric=send_unlock value_ms=3.174 node=client flow=10.1.0.16:50094-10.1.2.231:8080
metric=fct value_ms=10578.487 node=client flow=10.1.0.16:50094-10.1.2.231:8080
metric=send_unlock value_ms=2.678 node=client flow=10.1.0.16:50110-10.1.2.231:8080
metric=fct value_ms=26277.470 node=client flow=10.1.0.16:50110-10.1.2.231:8080
metric=send_unlock value_ms=1.932 node=client flow=10.1.0.16:50124-10.1.2.231:8080
metric=fct value_ms=6540.918 node=client flow=10.1.0.16:50124-10.1.2.231:8080
metric=send_unlock value_ms=0.694 node=client flow=10.1.0.16:50140-10.1.2.231:8080
metric=fct value_ms=5988.992 node=client flow=10.1.0.16:50140-10.1.2.231:8080
metric=send_unlock value_ms=30.055 node=client flow=10.1.0.16:56520-10.1.2.231:8081
metric=fct value_ms=6206.427 node=client flow=10.1.0.16:56520-10.1.2.231:8081
metric=send_unlock value_ms=29.352 node=client flow=10.1.0.16:56536-10.1.2.231:8081
metric=fct value_ms=23025.369 node=client flow=10.1.0.16:56536-10.1.2.231:8081
metric=send_unlock value_ms=28.781 node=client flow=10.1.0.16:56540-10.1.2.231:8081
metric=fct value_ms=10187.795 node=client flow=10.1.0.16:56540-10.1.2.231:8081
metric=send_unlock value_ms=28.888 node=client flow=10.1.0.16:56554-10.1.2.231:8081
metric=fct value_ms=6351.472 node=client flow=10.1.0.16:56554-10.1.2.231:8081
metric=send_unlock value_ms=28.140 node=client flow=10.1.0.16:56568-10.1.2.231:8081
metric=fct value_ms=6311.474 node=client flow=10.1.0.16:56568-10.1.2.231:8081
metric=send_unlock value_ms=28.238 node=client flow=10.1.0.16:56582-10.1.2.231:8081
metric=fct value_ms=35341.526 node=client flow=10.1.0.16:56582-10.1.2.231:8081
metric=send_unlock value_ms=27.506 node=client flow=10.1.0.16:56596-10.1.2.231:8081
metric=fct value_ms=6506.023 node=client flow=10.1.0.16:56596-10.1.2.231:8081
metric=send_unlock value_ms=27.610 node=client flow=10.1.0.16:56600-10.1.2.231:8081
metric=fct value_ms=13481.058 node=client flow=10.1.0.16:56600-10.1.2.231:8081
metric=send_unlock value_ms=26.890 node=client flow=10.1.0.16:56604-10.1.2.231:8081
metric=fct value_ms=6522.841 node=client flow=10.1.0.16:56604-10.1.2.231:8081
metric=send_unlock value_ms=26.987 node=client flow=10.1.0.16:56616-10.1.2.231:8081
metric=fct value_ms=10569.763 node=client flow=10.1.0.16:56616-10.1.2.231:8081
metric=send_unlock value_ms=26.699 node=client flow=10.1.0.16:56618-10.1.2.231:8081
metric=fct value_ms=8621.312 node=client flow=10.1.0.16:56618-10.1.2.231:8081
metric=send_unlock value_ms=26.522 node=client flow=10.1.0.16:56626-10.1.2.231:8081
metric=fct value_ms=8001.190 node=client flow=10.1.0.16:56626-10.1.2.231:8081
metric=send_unlock value_ms=25.650 node=client flow=10.1.0.16:56632-10.1.2.231:8081
metric=fct value_ms=34601.285 node=client flow=10.1.0.16:56632-10.1.2.231:8081
metric=send_unlock value_ms=25.890 node=client flow=10.1.0.16:56648-10.1.2.231:8081
metric=fct value_ms=27204.045 node=client flow=10.1.0.16:56648-10.1.2.231:8081
metric=send_unlock value_ms=25.148 node=client flow=10.1.0.16:56658-10.1.2.231:8081
metric=fct value_ms=27880.769 node=client flow=10.1.0.16:56658-10.1.2.231:8081
metric=send_unlock value_ms=25.004 node=client flow=10.1.0.16:56662-10.1.2.231:8081
metric=fct value_ms=6180.363 node=client flow=10.1.0.16:56662-10.1.2.231:8081
metric=send_unlock value_ms=23.702 node=client flow=10.1.0.16:56674-10.1.2.231:8081
metric=fct value_ms=7382.466 node=client flow=10.1.0.16:56674-10.1.2.231:8081
metric=send_unlock value_ms=24.165 node=client flow=10.1.0.16:56678-10.1.2.231:8081
metric=fct value_ms=9920.733 node=client flow=10.1.0.16:56678-10.1.2.231:8081
metric=send_unlock value_ms=23.011 node=client flow=10.1.0.16:56688-10.1.2.231:8081
metric=fct value_ms=6702.206 node=client flow=10.1.0.16:56688-10.1.2.231:8081
metric=send_unlock value_ms=23.014 node=client flow=10.1.0.16:56694-10.1.2.231:8081
metric=fct value_ms=8820.927 node=client flow=10.1.0.16:56694-10.1.2.231:8081
metric=send_unlock value_ms=22.943 node=client flow=10.1.0.16:56702-10.1.2.231:8081
metric=fct value_ms=13476.312 node=client flow=10.1.0.16:56702-10.1.2.231:8081
metric=send_unlock value_ms=22.745 node=client flow=10.1.0.16:56712-10.1.2.231:8081
metric=fct value_ms=6806.666 node=client flow=10.1.0.16:56712-10.1.2.231:8081
metric=send_unlock value_ms=19.738 node=client flow=10.1.0.16:38098-10.1.2.231:8082
metric=fct value_ms=19619.976 node=client flow=10.1.0.16:38098-10.1.2.231:8082
metric=send_unlock value_ms=18.719 node=client flow=10.1.0.16:38108-10.1.2.231:8082
metric=fct value_ms=8778.657 node=client flow=10.1.0.16:38108-10.1.2.231:8082
metric=send_unlock value_ms=18.717 node=client flow=10.1.0.16:38124-10.1.2.231:8082
metric=fct value_ms=7927.441 node=client flow=10.1.0.16:38124-10.1.2.231:8082
metric=send_unlock value_ms=18.165 node=client flow=10.1.0.16:38126-10.1.2.231:8082
metric=fct value_ms=14192.087 node=client flow=10.1.0.16:38126-10.1.2.231:8082
metric=send_unlock value_ms=20.326 node=client flow=10.1.0.16:56728-10.1.2.231:8081
metric=fct value_ms=20002.258 node=client flow=10.1.0.16:56728-10.1.2.231:8081
metric=send_unlock value_ms=17.373 node=client flow=10.1.0.16:38142-10.1.2.231:8082
metric=fct value_ms=23177.242 node=client flow=10.1.0.16:38142-10.1.2.231:8082
metric=send_unlock value_ms=17.428 node=client flow=10.1.0.16:38152-10.1.2.231:8082
metric=fct value_ms=10227.827 node=client flow=10.1.0.16:38152-10.1.2.231:8082
metric=send_unlock value_ms=16.724 node=client flow=10.1.0.16:38158-10.1.2.231:8082
metric=fct value_ms=15364.088 node=client flow=10.1.0.16:38158-10.1.2.231:8082
metric=send_unlock value_ms=16.326 node=client flow=10.1.0.16:38166-10.1.2.231:8082
metric=fct value_ms=5915.786 node=client flow=10.1.0.16:38166-10.1.2.231:8082
metric=send_unlock value_ms=15.781 node=client flow=10.1.0.16:38172-10.1.2.231:8082
metric=fct value_ms=6522.511 node=client flow=10.1.0.16:38172-10.1.2.231:8082
metric=send_unlock value_ms=15.278 node=client flow=10.1.0.16:38182-10.1.2.231:8082
metric=fct value_ms=14977.936 node=client flow=10.1.0.16:38182-10.1.2.231:8082
metric=send_unlock value_ms=14.434 node=client flow=10.1.0.16:38198-10.1.2.231:8082
metric=fct value_ms=10345.533 node=client flow=10.1.0.16:38198-10.1.2.231:8082
metric=send_unlock value_ms=14.008 node=client flow=10.1.0.16:38204-10.1.2.231:8082
metric=fct value_ms=7606.507 node=client flow=10.1.0.16:38204-10.1.2.231:8082
metric=send_unlock value_ms=13.866 node=client flow=10.1.0.16:38218-10.1.2.231:8082
metric=fct value_ms=22192.973 node=client flow=10.1.0.16:38218-10.1.2.231:8082
metric=send_unlock value_ms=13.258 node=client flow=10.1.0.16:38222-10.1.2.231:8082
metric=fct value_ms=7706.960 node=client flow=10.1.0.16:38222-10.1.2.231:8082
metric=send_unlock value_ms=12.899 node=client flow=10.1.0.16:38228-10.1.2.231:8082
metric=fct value_ms=21757.479 node=client flow=10.1.0.16:38228-10.1.2.231:8082
metric=send_unlock value_ms=12.886 node=client flow=10.1.0.16:38242-10.1.2.231:8082
metric=fct value_ms=32457.394 node=client flow=10.1.0.16:38242-10.1.2.231:8082
metric=send_unlock value_ms=12.146 node=client flow=10.1.0.16:38246-10.1.2.231:8082
metric=fct value_ms=10687.530 node=client flow=10.1.0.16:38246-10.1.2.231:8082
metric=send_unlock value_ms=11.583 node=client flow=10.1.0.16:38248-10.1.2.231:8082
metric=fct value_ms=7084.403 node=client flow=10.1.0.16:38248-10.1.2.231:8082
metric=send_unlock value_ms=11.564 node=client flow=10.1.0.16:38258-10.1.2.231:8082
metric=fct value_ms=16429.823 node=client flow=10.1.0.16:38258-10.1.2.231:8082
metric=send_unlock value_ms=11.931 node=client flow=10.1.0.16:38266-10.1.2.231:8082
metric=fct value_ms=7012.299 node=client flow=10.1.0.16:38266-10.1.2.231:8082
metric=send_unlock value_ms=11.542 node=client flow=10.1.0.16:38280-10.1.2.231:8082
metric=fct value_ms=6771.832 node=client flow=10.1.0.16:38280-10.1.2.231:8082
metric=send_unlock value_ms=10.969 node=client flow=10.1.0.16:38286-10.1.2.231:8082
metric=fct value_ms=6750.227 node=client flow=10.1.0.16:38286-10.1.2.231:8082
metric=send_unlock value_ms=12.034 node=client flow=10.1.0.16:47766-10.1.2.231:8083
metric=fct value_ms=33798.766 node=client flow=10.1.0.16:47766-10.1.2.231:8083
metric=send_unlock value_ms=10.438 node=client flow=10.1.0.16:38300-10.1.2.231:8082
metric=fct value_ms=9645.049 node=client flow=10.1.0.16:38300-10.1.2.231:8082
metric=send_unlock value_ms=11.542 node=client flow=10.1.0.16:47778-10.1.2.231:8083
metric=fct value_ms=6672.905 node=client flow=10.1.0.16:47778-10.1.2.231:8083
metric=send_unlock value_ms=10.440 node=client flow=10.1.0.16:47788-10.1.2.231:8083
metric=fct value_ms=9841.333 node=client flow=10.1.0.16:47788-10.1.2.231:8083
metric=send_unlock value_ms=10.441 node=client flow=10.1.0.16:47796-10.1.2.231:8083
metric=fct value_ms=16922.278 node=client flow=10.1.0.16:47796-10.1.2.231:8083
metric=send_unlock value_ms=9.805 node=client flow=10.1.0.16:47808-10.1.2.231:8083
metric=fct value_ms=25067.629 node=client flow=10.1.0.16:47808-10.1.2.231:8083
metric=send_unlock value_ms=10.234 node=client flow=10.1.0.16:47816-10.1.2.231:8083
metric=fct value_ms=21388.074 node=client flow=10.1.0.16:47816-10.1.2.231:8083
metric=send_unlock value_ms=9.383 node=client flow=10.1.0.16:47828-10.1.2.231:8083
metric=fct value_ms=10991.159 node=client flow=10.1.0.16:47828-10.1.2.231:8083
metric=send_unlock value_ms=8.872 node=client flow=10.1.0.16:47840-10.1.2.231:8083
metric=fct value_ms=6460.126 node=client flow=10.1.0.16:47840-10.1.2.231:8083
metric=send_unlock value_ms=8.882 node=client flow=10.1.0.16:47856-10.1.2.231:8083
metric=fct value_ms=36371.970 node=client flow=10.1.0.16:47856-10.1.2.231:8083
metric=send_unlock value_ms=8.153 node=client flow=10.1.0.16:47872-10.1.2.231:8083
metric=fct value_ms=16021.443 node=client flow=10.1.0.16:47872-10.1.2.231:8083
metric=send_unlock value_ms=7.891 node=client flow=10.1.0.16:47880-10.1.2.231:8083
metric=fct value_ms=38534.017 node=client flow=10.1.0.16:47880-10.1.2.231:8083
metric=send_unlock value_ms=8.196 node=client flow=10.1.0.16:47886-10.1.2.231:8083
metric=fct value_ms=9048.476 node=client flow=10.1.0.16:47886-10.1.2.231:8083
metric=send_unlock value_ms=7.631 node=client flow=10.1.0.16:47898-10.1.2.231:8083
metric=fct value_ms=34662.857 node=client flow=10.1.0.16:47898-10.1.2.231:8083
metric=send_unlock value_ms=7.370 node=client flow=10.1.0.16:47912-10.1.2.231:8083
metric=fct value_ms=15514.656 node=client flow=10.1.0.16:47912-10.1.2.231:8083
metric=send_unlock value_ms=6.953 node=client flow=10.1.0.16:47920-10.1.2.231:8083
metric=fct value_ms=15089.442 node=client flow=10.1.0.16:47920-10.1.2.231:8083
metric=send_unlock value_ms=6.253 node=client flow=10.1.0.16:47934-10.1.2.231:8083
metric=fct value_ms=16403.051 node=client flow=10.1.0.16:47934-10.1.2.231:8083
metric=send_unlock value_ms=6.183 node=client flow=10.1.0.16:47936-10.1.2.231:8083
metric=fct value_ms=8904.641 node=client flow=10.1.0.16:47936-10.1.2.231:8083
metric=send_unlock value_ms=4.262 node=client flow=10.1.0.16:38314-10.1.2.231:8082
metric=fct value_ms=13126.313 node=client flow=10.1.0.16:38314-10.1.2.231:8082
metric=send_unlock value_ms=4.637 node=client flow=10.1.0.16:47950-10.1.2.231:8083
metric=fct value_ms=12633.533 node=client flow=10.1.0.16:47950-10.1.2.231:8083
metric=send_unlock value_ms=4.508 node=client flow=10.1.0.16:47962-10.1.2.231:8083
metric=fct value_ms=12915.977 node=client flow=10.1.0.16:47962-10.1.2.231:8083
metric=send_unlock value_ms=3.981 node=client flow=10.1.0.16:47974-10.1.2.231:8083
metric=fct value_ms=6189.171 node=client flow=10.1.0.16:47974-10.1.2.231:8083
metric=send_unlock value_ms=3.875 node=client flow=10.1.0.16:47980-10.1.2.231:8083
metric=fct value_ms=7741.638 node=client flow=10.1.0.16:47980-10.1.2.231:8083
metric=send_unlock value_ms=5.055 node=client flow=10.1.0.16:56740-10.1.2.231:8081
metric=fct value_ms=7276.442 node=client flow=10.1.0.16:56740-10.1.2.231:8081
metric=send_unlock value_ms=3.244 node=client flow=10.1.0.16:47982-10.1.2.231:8083
metric=fct value_ms=7761.867 node=client flow=10.1.0.16:47982-10.1.2.231:8083
metric=send_unlock value_ms=3.054 node=client flow=10.1.0.16:47984-10.1.2.231:8083
metric=fct value_ms=6726.798 node=client flow=10.1.0.16:47984-10.1.2.231:8083
metric=send_unlock value_ms=1.667 node=client flow=10.1.0.16:47992-10.1.2.231:8083
metric=fct value_ms=21157.920 node=client flow=10.1.0.16:47992-10.1.2.231:8083
metric=send_unlock value_ms=0.267 node=client flow=10.1.0.16:38320-10.1.2.231:8082
metric=fct value_ms=6482.337 node=client flow=10.1.0.16:38320-10.1.2.231:8082
metric=send_unlock value_ms=1.859 node=client flow=10.1.0.16:48004-10.1.2.231:8083
metric=fct value_ms=11428.000 node=client flow=10.1.0.16:48004-10.1.2.231:8083
metric=send_unlock value_ms=0.935 node=client flow=10.1.0.16:56746-10.1.2.231:8081
metric=fct value_ms=7886.645 node=client flow=10.1.0.16:56746-10.1.2.231:8081
metric=server_gap value_ms=216.500 node=server flow=10.1.0.16:49916-10.1.2.231:8080
metric=server_gap value_ms=215.947 node=server flow=10.1.0.16:49930-10.1.2.231:8080
metric=server_gap value_ms=215.396 node=server flow=10.1.0.16:49944-10.1.2.231:8080
metric=server_gap value_ms=8.573 node=server flow=10.1.0.16:49948-10.1.2.231:8080
metric=server_gap value_ms=7.381 node=server flow=10.1.0.16:49956-10.1.2.231:8080
metric=server_gap value_ms=214.618 node=server flow=10.1.0.16:49958-10.1.2.231:8080
metric=server_gap value_ms=6.693 node=server flow=10.1.0.16:49974-10.1.2.231:8080
metric=server_gap value_ms=7.570 node=server flow=10.1.0.16:49976-10.1.2.231:8080
metric=server_gap value_ms=5.985 node=server flow=10.1.0.16:49990-10.1.2.231:8080
metric=server_gap value_ms=213.183 node=server flow=10.1.0.16:49998-10.1.2.231:8080
metric=server_gap value_ms=212.694 node=server flow=10.1.0.16:50002-10.1.2.231:8080
metric=server_gap value_ms=212.356 node=server flow=10.1.0.16:50010-10.1.2.231:8080
metric=server_gap value_ms=211.930 node=server flow=10.1.0.16:50022-10.1.2.231:8080
metric=server_gap value_ms=5.624 node=server flow=10.1.0.16:50032-10.1.2.231:8080
metric=server_gap value_ms=211.375 node=server flow=10.1.0.16:50036-10.1.2.231:8080
metric=server_gap value_ms=5.053 node=server flow=10.1.0.16:50050-10.1.2.231:8080
metric=server_gap value_ms=210.529 node=server flow=10.1.0.16:50066-10.1.2.231:8080
metric=server_gap value_ms=210.395 node=server flow=10.1.0.16:50070-10.1.2.231:8080
metric=server_gap value_ms=3.095 node=server flow=10.1.0.16:50080-10.1.2.231:8080
metric=server_gap value_ms=3.846 node=server flow=10.1.0.16:50082-10.1.2.231:8080
metric=server_gap value_ms=209.291 node=server flow=10.1.0.16:50092-10.1.2.231:8080
metric=server_gap value_ms=209.001 node=server flow=10.1.0.16:50094-10.1.2.231:8080
metric=server_gap value_ms=2.578 node=server flow=10.1.0.16:50110-10.1.2.231:8080
metric=server_gap value_ms=208.572 node=server flow=10.1.0.16:50124-10.1.2.231:8080
metric=server_gap value_ms=208.195 node=server flow=10.1.0.16:50140-10.1.2.231:8080
metric=server_gap value_ms=234.459 node=server flow=10.1.0.16:56520-10.1.2.231:8081
metric=server_gap value_ms=233.893 node=server flow=10.1.0.16:56536-10.1.2.231:8081
metric=server_gap value_ms=233.503 node=server flow=10.1.0.16:56540-10.1.2.231:8081
metric=server_gap value_ms=233.267 node=server flow=10.1.0.16:56554-10.1.2.231:8081
metric=server_gap value_ms=232.849 node=server flow=10.1.0.16:56568-10.1.2.231:8081
metric=server_gap value_ms=232.519 node=server flow=10.1.0.16:56582-10.1.2.231:8081
metric=server_gap value_ms=231.867 node=server flow=10.1.0.16:56596-10.1.2.231:8081
metric=server_gap value_ms=232.090 node=server flow=10.1.0.16:56600-10.1.2.231:8081
metric=server_gap value_ms=231.215 node=server flow=10.1.0.16:56604-10.1.2.231:8081
metric=server_gap value_ms=231.050 node=server flow=10.1.0.16:56616-10.1.2.231:8081
metric=server_gap value_ms=26.677 node=server flow=10.1.0.16:56618-10.1.2.231:8081
metric=server_gap value_ms=238.301 node=server flow=10.1.0.16:56626-10.1.2.231:8081
metric=server_gap value_ms=25.663 node=server flow=10.1.0.16:56632-10.1.2.231:8081
metric=server_gap value_ms=233.613 node=server flow=10.1.0.16:56648-10.1.2.231:8081
metric=server_gap value_ms=236.983 node=server flow=10.1.0.16:56658-10.1.2.231:8081
metric=server_gap value_ms=25.060 node=server flow=10.1.0.16:56662-10.1.2.231:8081
metric=server_gap value_ms=228.439 node=server flow=10.1.0.16:56674-10.1.2.231:8081
metric=server_gap value_ms=228.211 node=server flow=10.1.0.16:56678-10.1.2.231:8081
metric=server_gap value_ms=227.793 node=server flow=10.1.0.16:56688-10.1.2.231:8081
metric=server_gap value_ms=22.980 node=server flow=10.1.0.16:56694-10.1.2.231:8081
metric=server_gap value_ms=234.970 node=server flow=10.1.0.16:56702-10.1.2.231:8081
metric=server_gap value_ms=230.739 node=server flow=10.1.0.16:56712-10.1.2.231:8081
metric=server_gap value_ms=226.635 node=server flow=10.1.0.16:38098-10.1.2.231:8082
metric=server_gap value_ms=225.843 node=server flow=10.1.0.16:38108-10.1.2.231:8082
metric=server_gap value_ms=225.967 node=server flow=10.1.0.16:38124-10.1.2.231:8082
metric=server_gap value_ms=225.335 node=server flow=10.1.0.16:38126-10.1.2.231:8082
metric=server_gap value_ms=225.155 node=server flow=10.1.0.16:56728-10.1.2.231:8081
metric=server_gap value_ms=17.401 node=server flow=10.1.0.16:38142-10.1.2.231:8082
metric=server_gap value_ms=224.555 node=server flow=10.1.0.16:38152-10.1.2.231:8082
metric=server_gap value_ms=223.844 node=server flow=10.1.0.16:38158-10.1.2.231:8082
metric=server_gap value_ms=223.132 node=server flow=10.1.0.16:38166-10.1.2.231:8082
metric=server_gap value_ms=222.401 node=server flow=10.1.0.16:38172-10.1.2.231:8082
metric=server_gap value_ms=15.240 node=server flow=10.1.0.16:38182-10.1.2.231:8082
metric=server_gap value_ms=14.489 node=server flow=10.1.0.16:38198-10.1.2.231:8082
metric=server_gap value_ms=220.885 node=server flow=10.1.0.16:38204-10.1.2.231:8082
metric=server_gap value_ms=220.570 node=server flow=10.1.0.16:38218-10.1.2.231:8082
metric=server_gap value_ms=220.270 node=server flow=10.1.0.16:38222-10.1.2.231:8082
metric=server_gap value_ms=219.664 node=server flow=10.1.0.16:38228-10.1.2.231:8082
metric=server_gap value_ms=219.656 node=server flow=10.1.0.16:38242-10.1.2.231:8082
metric=server_gap value_ms=12.141 node=server flow=10.1.0.16:38246-10.1.2.231:8082
metric=server_gap value_ms=218.896 node=server flow=10.1.0.16:38248-10.1.2.231:8082
metric=server_gap value_ms=218.491 node=server flow=10.1.0.16:38258-10.1.2.231:8082
metric=server_gap value_ms=218.436 node=server flow=10.1.0.16:38266-10.1.2.231:8082
metric=server_gap value_ms=11.488 node=server flow=10.1.0.16:38280-10.1.2.231:8082
metric=server_gap value_ms=217.879 node=server flow=10.1.0.16:38286-10.1.2.231:8082
metric=server_gap value_ms=217.665 node=server flow=10.1.0.16:47766-10.1.2.231:8083
metric=server_gap value_ms=217.142 node=server flow=10.1.0.16:38300-10.1.2.231:8082
metric=server_gap value_ms=216.779 node=server flow=10.1.0.16:47778-10.1.2.231:8083
metric=server_gap value_ms=216.141 node=server flow=10.1.0.16:47788-10.1.2.231:8083
metric=server_gap value_ms=10.456 node=server flow=10.1.0.16:47796-10.1.2.231:8083
metric=server_gap value_ms=9.796 node=server flow=10.1.0.16:47808-10.1.2.231:8083
metric=server_gap value_ms=215.426 node=server flow=10.1.0.16:47816-10.1.2.231:8083
metric=server_gap value_ms=215.047 node=server flow=10.1.0.16:47828-10.1.2.231:8083
metric=server_gap value_ms=214.836 node=server flow=10.1.0.16:47840-10.1.2.231:8083
metric=server_gap value_ms=214.357 node=server flow=10.1.0.16:47856-10.1.2.231:8083
metric=server_gap value_ms=214.292 node=server flow=10.1.0.16:47872-10.1.2.231:8083
metric=server_gap value_ms=213.656 node=server flow=10.1.0.16:47880-10.1.2.231:8083
metric=server_gap value_ms=8.245 node=server flow=10.1.0.16:47886-10.1.2.231:8083
metric=server_gap value_ms=212.878 node=server flow=10.1.0.16:47898-10.1.2.231:8083
metric=server_gap value_ms=212.607 node=server flow=10.1.0.16:47912-10.1.2.231:8083
metric=server_gap value_ms=212.006 node=server flow=10.1.0.16:47920-10.1.2.231:8083
metric=server_gap value_ms=212.043 node=server flow=10.1.0.16:47934-10.1.2.231:8083
metric=server_gap value_ms=211.407 node=server flow=10.1.0.16:47936-10.1.2.231:8083
metric=server_gap value_ms=210.934 node=server flow=10.1.0.16:38314-10.1.2.231:8082
metric=server_gap value_ms=210.698 node=server flow=10.1.0.16:47950-10.1.2.231:8083
metric=server_gap value_ms=4.479 node=server flow=10.1.0.16:47962-10.1.2.231:8083
metric=server_gap value_ms=4.074 node=server flow=10.1.0.16:47974-10.1.2.231:8083
metric=server_gap value_ms=209.676 node=server flow=10.1.0.16:47980-10.1.2.231:8083
metric=server_gap value_ms=212.810 node=server flow=10.1.0.16:56740-10.1.2.231:8081
metric=server_gap value_ms=3.264 node=server flow=10.1.0.16:47982-10.1.2.231:8083
metric=server_gap value_ms=208.375 node=server flow=10.1.0.16:47984-10.1.2.231:8083
metric=server_gap value_ms=1.641 node=server flow=10.1.0.16:47992-10.1.2.231:8083
metric=server_gap value_ms=207.582 node=server flow=10.1.0.16:38320-10.1.2.231:8082
metric=server_gap value_ms=207.220 node=server flow=10.1.0.16:48004-10.1.2.231:8083
metric=server_gap value_ms=205.588 node=server flow=10.1.0.16:56746-10.1.2.231:8081
```
