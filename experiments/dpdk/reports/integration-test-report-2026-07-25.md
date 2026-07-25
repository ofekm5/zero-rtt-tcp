# Integration Test Report — 2026-07-25

**Implementation**: DPDK (T8 ISN ack-num translation shift)
**ClientNIC binary**: `src/clientnic/dpdk-forwarder/` (transparent forwarder + V-stamp)
**ServerNIC binary**: `src/servernic/dpdk/` (full translator)
**Experiment script**: `experiments/dpdk/run_experiment.sh`
**Node scripts**: `experiments/dpdk/` (clientnic/servernic), `experiments/nodes/` (client/server)
**Overall result**: ALL PASSED

## Latency Summary (TTFB @ 3 points + FCT)

```
  clientnic TTFB (in-app): no samples found
  servernic TTFB (in-app): no samples found
  Client TTFB   : no samples found
  Client FCT    : no samples found
  Pcap FCT      : n=100  min=116.845  mean=422.991  median=472.077  max=674.377 ms
  Send unlock   : n=100  min=1.699  mean=22.291  median=22.603  max=37.502 ms
  Server gap    : n=100  min=3.128  mean=36.216  median=27.556  max=257.675 ms
```

## Client Output

```
--- Round 1/1: 1 port(s) [8080-8080] x 100 parallel = 100 conns ---
------------------------------------------------------------
Client connecting to 10.1.2.143, TCP port 8080
TCP window size: 0.11 MByte (default)
------------------------------------------------------------
[ 72] local 10.1.0.178 port 37824 connected with 10.1.2.143 port 8080
[  3] local 10.1.0.178 port 37158 connected with 10.1.2.143 port 8080
[  5] local 10.1.0.178 port 37188 connected with 10.1.2.143 port 8080
[  4] local 10.1.0.178 port 37174 connected with 10.1.2.143 port 8080
[  6] local 10.1.0.178 port 37198 connected with 10.1.2.143 port 8080
[ 18] local 10.1.0.178 port 37330 connected with 10.1.2.143 port 8080
[  9] local 10.1.0.178 port 37220 connected with 10.1.2.143 port 8080
[  7] local 10.1.0.178 port 37208 connected with 10.1.2.143 port 8080
[  8] local 10.1.0.178 port 37210 connected with 10.1.2.143 port 8080
[ 10] local 10.1.0.178 port 37236 connected with 10.1.2.143 port 8080
[ 12] local 10.1.0.178 port 37268 connected with 10.1.2.143 port 8080
[ 16] local 10.1.0.178 port 37312 connected with 10.1.2.143 port 8080
[ 19] local 10.1.0.178 port 37344 connected with 10.1.2.143 port 8080
[ 25] local 10.1.0.178 port 37410 connected with 10.1.2.143 port 8080
[ 23] local 10.1.0.178 port 37398 connected with 10.1.2.143 port 8080
[ 26] local 10.1.0.178 port 37424 connected with 10.1.2.143 port 8080
[ 29] local 10.1.0.178 port 37452 connected with 10.1.2.143 port 8080
[ 31] local 10.1.0.178 port 37474 connected with 10.1.2.143 port 8080
[ 27] local 10.1.0.178 port 37432 connected with 10.1.2.143 port 8080
[ 36] local 10.1.0.178 port 37516 connected with 10.1.2.143 port 8080
[ 35] local 10.1.0.178 port 37504 connected with 10.1.2.143 port 8080
[ 40] local 10.1.0.178 port 37544 connected with 10.1.2.143 port 8080
[ 44] local 10.1.0.178 port 37584 connected with 10.1.2.143 port 8080
[ 47] local 10.1.0.178 port 37622 connected with 10.1.2.143 port 8080
[ 91] local 10.1.0.178 port 37998 connected with 10.1.2.143 port 8080
[ 90] local 10.1.0.178 port 37986 connected with 10.1.2.143 port 8080
[ 67] local 10.1.0.178 port 37764 connected with 10.1.2.143 port 8080
[ 69] local 10.1.0.178 port 37794 connected with 10.1.2.143 port 8080
[103] local 10.1.0.178 port 38098 connected with 10.1.2.143 port 8080
[ 11] local 10.1.0.178 port 37252 connected with 10.1.2.143 port 8080
[ 13] local 10.1.0.178 port 37280 connected with 10.1.2.143 port 8080
[ 15] local 10.1.0.178 port 37302 connected with 10.1.2.143 port 8080
[ 70] local 10.1.0.178 port 37798 connected with 10.1.2.143 port 8080
[ 17] local 10.1.0.178 port 37314 connected with 10.1.2.143 port 8080
[ 78] local 10.1.0.178 port 37854 connected with 10.1.2.143 port 8080
[ 14] local 10.1.0.178 port 37286 connected with 10.1.2.143 port 8080
[ 97] local 10.1.0.178 port 38052 connected with 10.1.2.143 port 8080
[ 20] local 10.1.0.178 port 37358 connected with 10.1.2.143 port 8080
[ 77] local 10.1.0.178 port 37848 connected with 10.1.2.143 port 8080
[ 54] local 10.1.0.178 port 37672 connected with 10.1.2.143 port 8080
[ 76] local 10.1.0.178 port 37844 connected with 10.1.2.143 port 8080
[ 80] local 10.1.0.178 port 37884 connected with 10.1.2.143 port 8080
[ 21] local 10.1.0.178 port 37368 connected with 10.1.2.143 port 8080
[ 83] local 10.1.0.178 port 37916 connected with 10.1.2.143 port 8080
[ 22] local 10.1.0.178 port 37384 connected with 10.1.2.143 port 8080
[ 86] local 10.1.0.178 port 37940 connected with 10.1.2.143 port 8080
[ 49] local 10.1.0.178 port 37632 connected with 10.1.2.143 port 8080
[ 64] local 10.1.0.178 port 37742 connected with 10.1.2.143 port 8080
[ 34] local 10.1.0.178 port 37496 connected with 10.1.2.143 port 8080
[ 42] local 10.1.0.178 port 37574 connected with 10.1.2.143 port 8080
[ 75] local 10.1.0.178 port 37838 connected with 10.1.2.143 port 8080
[ 28] local 10.1.0.178 port 37438 connected with 10.1.2.143 port 8080
[ 96] local 10.1.0.178 port 38030 connected with 10.1.2.143 port 8080
[ 82] local 10.1.0.178 port 37908 connected with 10.1.2.143 port 8080
[ 65] local 10.1.0.178 port 37756 connected with 10.1.2.143 port 8080
[ 87] local 10.1.0.178 port 37956 connected with 10.1.2.143 port 8080
[ 24] local 10.1.0.178 port 37408 connected with 10.1.2.143 port 8080
[ 51] local 10.1.0.178 port 37652 connected with 10.1.2.143 port 8080
[ 52] local 10.1.0.178 port 37658 connected with 10.1.2.143 port 8080
[ 43] local 10.1.0.178 port 37578 connected with 10.1.2.143 port 8080
[ 56] local 10.1.0.178 port 37682 connected with 10.1.2.143 port 8080
[ 58] local 10.1.0.178 port 37692 connected with 10.1.2.143 port 8080
[ 38] local 10.1.0.178 port 37522 connected with 10.1.2.143 port 8080
[ 37] local 10.1.0.178 port 37520 connected with 10.1.2.143 port 8080
[ 57] local 10.1.0.178 port 37688 connected with 10.1.2.143 port 8080
[ 59] local 10.1.0.178 port 37696 connected with 10.1.2.143 port 8080
[ 60] local 10.1.0.178 port 37694 connected with 10.1.2.143 port 8080
[ 61] local 10.1.0.178 port 37706 connected with 10.1.2.143 port 8080
[ 32] local 10.1.0.178 port 37482 connected with 10.1.2.143 port 8080
[ 55] local 10.1.0.178 port 37676 connected with 10.1.2.143 port 8080
[ 85] local 10.1.0.178 port 37932 connected with 10.1.2.143 port 8080
[ 88] local 10.1.0.178 port 37966 connected with 10.1.2.143 port 8080
[ 81] local 10.1.0.178 port 37892 connected with 10.1.2.143 port 8080
[ 98] local 10.1.0.178 port 38064 connected with 10.1.2.143 port 8080
[ 33] local 10.1.0.178 port 37494 connected with 10.1.2.143 port 8080
[ 94] local 10.1.0.178 port 38014 connected with 10.1.2.143 port 8080
[ 74] local 10.1.0.178 port 37828 connected with 10.1.2.143 port 8080
[ 73] local 10.1.0.178 port 37826 connected with 10.1.2.143 port 8080
[ 84] local 10.1.0.178 port 37930 connected with 10.1.2.143 port 8080
[ 41] local 10.1.0.178 port 37560 connected with 10.1.2.143 port 8080
[ 66] local 10.1.0.178 port 37758 connected with 10.1.2.143 port 8080
[ 79] local 10.1.0.178 port 37868 connected with 10.1.2.143 port 8080
[ 95] local 10.1.0.178 port 38036 connected with 10.1.2.143 port 8080
[ 89] local 10.1.0.178 port 37980 connected with 10.1.2.143 port 8080
[ 62] local 10.1.0.178 port 37722 connected with 10.1.2.143 port 8080
[ 92] local 10.1.0.178 port 38012 connected with 10.1.2.143 port 8080
[ 30] local 10.1.0.178 port 37468 connected with 10.1.2.143 port 8080
[ 39] local 10.1.0.178 port 37532 connected with 10.1.2.143 port 8080
[ 93] local 10.1.0.178 port 38008 connected with 10.1.2.143 port 8080
[ 48] local 10.1.0.178 port 37630 connected with 10.1.2.143 port 8080
[ 53] local 10.1.0.178 port 37664 connected with 10.1.2.143 port 8080
[ 46] local 10.1.0.178 port 37600 connected with 10.1.2.143 port 8080
[ 50] local 10.1.0.178 port 37648 connected with 10.1.2.143 port 8080
[ 99] local 10.1.0.178 port 38078 connected with 10.1.2.143 port 8080
[ 45] local 10.1.0.178 port 37612 connected with 10.1.2.143 port 8080
[ 63] local 10.1.0.178 port 37726 connected with 10.1.2.143 port 8080
[ 68] local 10.1.0.178 port 37780 connected with 10.1.2.143 port 8080
[100] local 10.1.0.178 port 38086 connected with 10.1.2.143 port 8080
[ 71] local 10.1.0.178 port 37812 connected with 10.1.2.143 port 8080
[101] local 10.1.0.178 port 38096 connected with 10.1.2.143 port 8080
[ ID] Interval       Transfer     Bandwidth
[ 16]  0.0- 0.1 sec  1.00 MBytes   140 Mbits/sec
[ 36]  0.0- 0.1 sec  1.00 MBytes   155 Mbits/sec
[ 40]  0.0- 0.1 sec  1.00 MBytes   134 Mbits/sec
[ 42]  0.0- 0.1 sec  1.00 MBytes   155 Mbits/sec
[ 44]  0.0- 0.1 sec  1.00 MBytes  92.5 Mbits/sec
[ 13]  0.0- 0.1 sec  1.00 MBytes  91.7 Mbits/sec
[ 14]  0.0- 0.1 sec  1.00 MBytes  88.1 Mbits/sec
[ 38]  0.0- 0.1 sec  1.00 MBytes  76.4 Mbits/sec
[ 32]  0.0- 0.1 sec  1.00 MBytes  83.9 Mbits/sec
[ 23]  0.0- 0.1 sec  1.00 MBytes  67.2 Mbits/sec
[ 31]  0.0- 0.1 sec  1.00 MBytes  69.3 Mbits/sec
[ 35]  0.0- 0.1 sec  1.00 MBytes  65.5 Mbits/sec
[ 24]  0.0- 0.1 sec  1.00 MBytes  64.3 Mbits/sec
[  4]  0.0- 0.2 sec  1.00 MBytes  54.3 Mbits/sec
[  9]  0.0- 0.1 sec  1.00 MBytes  56.5 Mbits/sec
[ 11]  0.0- 0.2 sec  1.00 MBytes  55.7 Mbits/sec
[ 21]  0.0- 0.1 sec  1.00 MBytes  57.9 Mbits/sec
[ 34]  0.0- 0.1 sec  1.00 MBytes  60.1 Mbits/sec
[ 43]  0.0- 0.1 sec  1.00 MBytes  56.9 Mbits/sec
[ 37]  0.0- 0.1 sec  1.00 MBytes  58.8 Mbits/sec
[ 33]  0.0- 0.1 sec  1.00 MBytes  62.2 Mbits/sec
[  3]  0.0- 0.2 sec  1.00 MBytes  50.0 Mbits/sec
[ 25]  0.0- 0.2 sec  1.00 MBytes  47.1 Mbits/sec
[ 29]  0.0- 0.2 sec  1.00 MBytes  45.0 Mbits/sec
[ 17]  0.0- 0.2 sec  1.00 MBytes  46.3 Mbits/sec
[ 22]  0.0- 0.2 sec  1.00 MBytes  52.9 Mbits/sec
[  7]  0.0- 0.2 sec  1.00 MBytes  43.2 Mbits/sec
[ 12]  0.0- 0.2 sec  1.00 MBytes  41.5 Mbits/sec
[ 15]  0.0- 0.2 sec  1.00 MBytes  43.6 Mbits/sec
[ 19]  0.0- 0.2 sec  1.00 MBytes  37.8 Mbits/sec
[ 27]  0.0- 0.2 sec  1.00 MBytes  38.4 Mbits/sec
[ 20]  0.0- 0.2 sec  1.00 MBytes  38.8 Mbits/sec
[  8]  0.0- 0.2 sec  1.00 MBytes  35.3 Mbits/sec
[ 10]  0.0- 0.3 sec  1.00 MBytes  33.2 Mbits/sec
[ 26]  0.0- 0.2 sec  1.00 MBytes  33.9 Mbits/sec
[ 28]  0.0- 0.2 sec  1.00 MBytes  34.2 Mbits/sec
[ 62]  0.0- 0.3 sec  1.00 MBytes  30.6 Mbits/sec
[ 50]  0.0- 0.3 sec  1.00 MBytes  31.8 Mbits/sec
[ 82]  0.0- 0.3 sec  1.00 MBytes  28.5 Mbits/sec
[ 30]  0.0- 0.3 sec  1.00 MBytes  29.0 Mbits/sec
[ 54]  0.0- 0.3 sec  1.00 MBytes  28.0 Mbits/sec
[ 55]  0.0- 0.3 sec  1.00 MBytes  25.5 Mbits/sec
[ 84]  0.0- 0.3 sec  1.00 MBytes  26.2 Mbits/sec
[ 47]  0.0- 0.4 sec  1.00 MBytes  23.5 Mbits/sec
[ 52]  0.0- 0.3 sec  1.00 MBytes  24.6 Mbits/sec
[ 78]  0.0- 0.4 sec  1.00 MBytes  22.6 Mbits/sec
[ 97]  0.0- 0.4 sec  1.00 MBytes  22.4 Mbits/sec
[ 49]  0.0- 0.4 sec  1.00 MBytes  22.4 Mbits/sec
[ 65]  0.0- 0.4 sec  1.00 MBytes  22.3 Mbits/sec
[ 18]  0.0- 0.4 sec  1.00 MBytes  21.5 Mbits/sec
[ 88]  0.0- 0.4 sec  1.00 MBytes  21.7 Mbits/sec
[  6]  0.0- 0.4 sec  1.00 MBytes  20.6 Mbits/sec
[ 58]  0.0- 0.4 sec  1.00 MBytes  20.1 Mbits/sec
[ 80]  0.0- 0.4 sec  1.00 MBytes  19.7 Mbits/sec
[ 87]  0.0- 0.4 sec  1.00 MBytes  19.5 Mbits/sec
[ 73]  0.0- 0.4 sec  1.00 MBytes  18.9 Mbits/sec
[ 39]  0.0- 0.4 sec  1.00 MBytes  19.2 Mbits/sec
[ 53]  0.0- 0.4 sec  1.00 MBytes  19.3 Mbits/sec
[ 45]  0.0- 0.4 sec  1.00 MBytes  19.7 Mbits/sec
[ 67]  0.0- 0.4 sec  1.00 MBytes  18.7 Mbits/sec
[103]  0.0- 0.5 sec  1.00 MBytes  18.0 Mbits/sec
[ 86]  0.0- 0.5 sec  1.00 MBytes  18.1 Mbits/sec
[ 59]  0.0- 0.5 sec  1.00 MBytes  17.8 Mbits/sec
[ 81]  0.0- 0.5 sec  1.00 MBytes  18.5 Mbits/sec
[ 63]  0.0- 0.5 sec  1.00 MBytes  18.0 Mbits/sec
[ 72]  0.0- 0.5 sec  1.00 MBytes  16.4 Mbits/sec
[ 91]  0.0- 0.5 sec  1.00 MBytes  16.4 Mbits/sec
[ 90]  0.0- 0.5 sec  1.00 MBytes  17.3 Mbits/sec
[ 69]  0.0- 0.5 sec  1.00 MBytes  17.6 Mbits/sec
[ 77]  0.0- 0.5 sec  1.00 MBytes  16.8 Mbits/sec
[ 64]  0.0- 0.5 sec  1.00 MBytes  17.8 Mbits/sec
[ 75]  0.0- 0.5 sec  1.00 MBytes  17.4 Mbits/sec
[ 56]  0.0- 0.5 sec  1.00 MBytes  17.2 Mbits/sec
[ 60]  0.0- 0.5 sec  1.00 MBytes  16.7 Mbits/sec
[ 98]  0.0- 0.5 sec  1.00 MBytes  16.6 Mbits/sec
[ 41]  0.0- 0.5 sec  1.00 MBytes  17.5 Mbits/sec
[  5]  0.0- 0.5 sec  1.00 MBytes  16.3 Mbits/sec
[ 70]  0.0- 0.5 sec  1.00 MBytes  16.0 Mbits/sec
[ 76]  0.0- 0.5 sec  1.00 MBytes  15.8 Mbits/sec
[ 57]  0.0- 0.5 sec  1.00 MBytes  16.3 Mbits/sec
[ 66]  0.0- 0.5 sec  1.00 MBytes  16.0 Mbits/sec
[ 48]  0.0- 0.6 sec  1.00 MBytes  15.2 Mbits/sec
[ 99]  0.0- 0.5 sec  1.00 MBytes  15.5 Mbits/sec
[ 83]  0.0- 0.6 sec  1.00 MBytes  14.8 Mbits/sec
[ 96]  0.0- 0.6 sec  1.00 MBytes  15.1 Mbits/sec
[ 51]  0.0- 0.6 sec  1.00 MBytes  14.5 Mbits/sec
[ 61]  0.0- 0.6 sec  1.00 MBytes  14.9 Mbits/sec
[ 85]  0.0- 0.6 sec  1.00 MBytes  14.8 Mbits/sec
[ 94]  0.0- 0.6 sec  1.00 MBytes  14.6 Mbits/sec
[ 74]  0.0- 0.6 sec  1.00 MBytes  14.6 Mbits/sec
[ 79]  0.0- 0.6 sec  1.00 MBytes  14.7 Mbits/sec
[ 95]  0.0- 0.6 sec  1.00 MBytes  14.5 Mbits/sec
[ 89]  0.0- 0.6 sec  1.00 MBytes  14.9 Mbits/sec
[ 92]  0.0- 0.6 sec  1.00 MBytes  15.0 Mbits/sec
[100]  0.0- 0.6 sec  1.00 MBytes  14.7 Mbits/sec
[101]  0.0- 0.6 sec  1.00 MBytes  15.1 Mbits/sec
[ 93]  0.0- 0.6 sec  1.00 MBytes  14.4 Mbits/sec
[ 68]  0.0- 0.6 sec  1.00 MBytes  14.4 Mbits/sec
[ 71]  0.0- 0.6 sec  1.00 MBytes  14.3 Mbits/sec
[ 46]  0.0- 0.6 sec  1.00 MBytes  13.9 Mbits/sec
[SUM]  0.0- 0.6 sec   100 MBytes  1388 Mbits/sec
Success: 1/1
```

## ClientNIC Log (0-RTT activity)

```
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x12906e2d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x0d99cfcc in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xe2f1839f in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x743986a7 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9aecd984 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x5726da61 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xff284f5e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xd28c1d69 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8738144d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xfcd7320b in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xac44a422 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x82b11fda in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa504435d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x9492709e in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xebe4ae4d in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x8d46c2c9 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x99b6aeca in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x1d989e57 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x55ba483c in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x7f708625 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x14fb5222 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x34202fc5 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0x3f4f5747 in ack-num
FORWARDER: SYN: spoofed SYN-ACK sent, SYN forwarded with V=0xa380d25d in ack-num
FORWARDER: stats client-facing (port 1): rx=73772 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61065 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5185/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73772 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61065 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5185/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73772 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61065 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5185/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73773 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61066 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5187/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73773 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61066 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5187/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73773 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61066 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5187/8191 low-water=4236
FORWARDER: stats client-facing (port 1): rx=73773 tx=61165 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats ServerNIC-facing (port 0): rx=61066 tx=73772 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
FORWARDER: stats mempool: avail=5187/8191 low-water=4236
FORWARDER: Shutting down...
ena_rx_queue_release(): Rx queue 1:0 released
ena_tx_queue_release(): Tx queue 1:0 released
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
```

## ServerNIC Log

```
SERVERNIC: stats mempool: avail=5670/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72509 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61166 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5670/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72509 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61166 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5670/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72509 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61166 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5670/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72509 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61166 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5670/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72510 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61167 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5672/8191 low-water=4273
SERVERNIC: stats ClientNIC-facing (port 0): rx=72510 tx=61065 imissed=1264 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats ClientNIC-facing (port 0): imissed=1264 ? RX ring overflowed, core too slow (capacity-model ?11)
SERVERNIC: stats Server-facing (port 1): rx=61167 tx=72508 imissed=0 rx_nombuf=0 ierrors=0 oerrors=0
SERVERNIC: stats mempool: avail=5672/8191 low-water=4273
SERVERNIC: Shutting down...
ena_rx_queue_release(): Rx queue 0:0 released
ena_tx_queue_release(): Tx queue 0:0 released
ena_rx_queue_release(): Rx queue 1:0 released
ena_tx_queue_release(): Tx queue 1:0 released
```

## Server Log

```
[ 46]  0.0- 0.5 sec  1.00 MBytes  15.3 Mbits/sec
[ 13]  0.0- 0.6 sec  1.00 MBytes  15.2 Mbits/sec
[ 14]  0.0- 0.6 sec  1.00 MBytes  13.9 Mbits/sec
[ 30]  0.0- 0.6 sec  1.00 MBytes  14.4 Mbits/sec
[ 64]  0.0- 0.6 sec  1.00 MBytes  14.5 Mbits/sec
[ 72]  0.0- 0.6 sec  1.00 MBytes  14.2 Mbits/sec
[ 60]  0.0- 0.6 sec  1.00 MBytes  14.4 Mbits/sec
[ 65]  0.0- 0.6 sec  1.00 MBytes  13.9 Mbits/sec
[ 67]  0.0- 0.6 sec  1.00 MBytes  14.3 Mbits/sec
[ 71]  0.0- 0.6 sec  1.00 MBytes  14.0 Mbits/sec
[ 50]  0.0- 0.6 sec  1.00 MBytes  14.1 Mbits/sec
[ 54]  0.0- 0.6 sec  1.00 MBytes  14.5 Mbits/sec
[ 66]  0.0- 0.6 sec  1.00 MBytes  14.3 Mbits/sec
[ 56]  0.0- 0.6 sec  1.00 MBytes  14.2 Mbits/sec
[ 44]  0.0- 0.6 sec  1.00 MBytes  13.8 Mbits/sec
[ 39]  0.0- 0.6 sec  1.00 MBytes  13.8 Mbits/sec
[ 21]  0.0- 0.6 sec  1.00 MBytes  13.7 Mbits/sec
[ 63]  0.0- 0.6 sec  1.00 MBytes  13.4 Mbits/sec
[ 47]  0.0- 0.6 sec  1.00 MBytes  13.3 Mbits/sec
[SUM]  0.0- 0.6 sec   100 MBytes  1.33 Gbits/sec
```

## Packet Analysis

```
metric=send_unlock value_ms=37.502 node=client flow=10.1.0.178:37158-10.1.2.143:8080
metric=fct value_ms=237.485 node=client flow=10.1.0.178:37158-10.1.2.143:8080
metric=send_unlock value_ms=37.020 node=client flow=10.1.0.178:37174-10.1.2.143:8080
metric=fct value_ms=212.814 node=client flow=10.1.0.178:37174-10.1.2.143:8080
metric=send_unlock value_ms=36.385 node=client flow=10.1.0.178:37188-10.1.2.143:8080
metric=fct value_ms=607.086 node=client flow=10.1.0.178:37188-10.1.2.143:8080
metric=send_unlock value_ms=35.778 node=client flow=10.1.0.178:37198-10.1.2.143:8080
metric=fct value_ms=501.625 node=client flow=10.1.0.178:37198-10.1.2.143:8080
metric=send_unlock value_ms=35.156 node=client flow=10.1.0.178:37208-10.1.2.143:8080
metric=fct value_ms=271.949 node=client flow=10.1.0.178:37208-10.1.2.143:8080
metric=send_unlock value_ms=34.548 node=client flow=10.1.0.178:37210-10.1.2.143:8080
metric=fct value_ms=312.031 node=client flow=10.1.0.178:37210-10.1.2.143:8080
metric=send_unlock value_ms=34.382 node=client flow=10.1.0.178:37220-10.1.2.143:8080
metric=fct value_ms=210.106 node=client flow=10.1.0.178:37220-10.1.2.143:8080
metric=send_unlock value_ms=33.882 node=client flow=10.1.0.178:37236-10.1.2.143:8080
metric=fct value_ms=311.320 node=client flow=10.1.0.178:37236-10.1.2.143:8080
metric=send_unlock value_ms=34.786 node=client flow=10.1.0.178:37252-10.1.2.143:8080
metric=fct value_ms=209.235 node=client flow=10.1.0.178:37252-10.1.2.143:8080
metric=send_unlock value_ms=33.226 node=client flow=10.1.0.178:37268-10.1.2.143:8080
metric=fct value_ms=292.456 node=client flow=10.1.0.178:37268-10.1.2.143:8080
metric=send_unlock value_ms=34.318 node=client flow=10.1.0.178:37280-10.1.2.143:8080
metric=fct value_ms=158.726 node=client flow=10.1.0.178:37280-10.1.2.143:8080
metric=send_unlock value_ms=34.114 node=client flow=10.1.0.178:37286-10.1.2.143:8080
metric=fct value_ms=158.154 node=client flow=10.1.0.178:37286-10.1.2.143:8080
metric=send_unlock value_ms=33.701 node=client flow=10.1.0.178:37302-10.1.2.143:8080
metric=fct value_ms=269.166 node=client flow=10.1.0.178:37302-10.1.2.143:8080
metric=send_unlock value_ms=31.898 node=client flow=10.1.0.178:37312-10.1.2.143:8080
metric=fct value_ms=126.325 node=client flow=10.1.0.178:37312-10.1.2.143:8080
metric=send_unlock value_ms=33.179 node=client flow=10.1.0.178:37314-10.1.2.143:8080
metric=fct value_ms=243.490 node=client flow=10.1.0.178:37314-10.1.2.143:8080
metric=send_unlock value_ms=31.415 node=client flow=10.1.0.178:37330-10.1.2.143:8080
metric=fct value_ms=454.384 node=client flow=10.1.0.178:37330-10.1.2.143:8080
metric=send_unlock value_ms=31.099 node=client flow=10.1.0.178:37344-10.1.2.143:8080
metric=fct value_ms=290.167 node=client flow=10.1.0.178:37344-10.1.2.143:8080
metric=send_unlock value_ms=32.844 node=client flow=10.1.0.178:37358-10.1.2.143:8080
metric=fct value_ms=290.081 node=client flow=10.1.0.178:37358-10.1.2.143:8080
metric=send_unlock value_ms=32.597 node=client flow=10.1.0.178:37368-10.1.2.143:8080
metric=fct value_ms=230.241 node=client flow=10.1.0.178:37368-10.1.2.143:8080
metric=send_unlock value_ms=32.121 node=client flow=10.1.0.178:37384-10.1.2.143:8080
metric=fct value_ms=225.827 node=client flow=10.1.0.178:37384-10.1.2.143:8080
metric=send_unlock value_ms=29.844 node=client flow=10.1.0.178:37398-10.1.2.143:8080
metric=fct value_ms=208.929 node=client flow=10.1.0.178:37398-10.1.2.143:8080
metric=send_unlock value_ms=32.831 node=client flow=10.1.0.178:37408-10.1.2.143:8080
metric=fct value_ms=173.573 node=client flow=10.1.0.178:37408-10.1.2.143:8080
metric=send_unlock value_ms=28.569 node=client flow=10.1.0.178:37410-10.1.2.143:8080
metric=fct value_ms=224.344 node=client flow=10.1.0.178:37410-10.1.2.143:8080
metric=send_unlock value_ms=28.529 node=client flow=10.1.0.178:37424-10.1.2.143:8080
metric=fct value_ms=305.706 node=client flow=10.1.0.178:37424-10.1.2.143:8080
metric=send_unlock value_ms=28.026 node=client flow=10.1.0.178:37432-10.1.2.143:8080
metric=fct value_ms=285.106 node=client flow=10.1.0.178:37432-10.1.2.143:8080
metric=send_unlock value_ms=31.210 node=client flow=10.1.0.178:37438-10.1.2.143:8080
metric=fct value_ms=305.193 node=client flow=10.1.0.178:37438-10.1.2.143:8080
metric=send_unlock value_ms=27.267 node=client flow=10.1.0.178:37452-10.1.2.143:8080
metric=fct value_ms=238.800 node=client flow=10.1.0.178:37452-10.1.2.143:8080
metric=send_unlock value_ms=33.250 node=client flow=10.1.0.178:37468-10.1.2.143:8080
metric=fct value_ms=349.378 node=client flow=10.1.0.178:37468-10.1.2.143:8080
metric=send_unlock value_ms=26.656 node=client flow=10.1.0.178:37474-10.1.2.143:8080
metric=fct value_ms=205.657 node=client flow=10.1.0.178:37474-10.1.2.143:8080
metric=send_unlock value_ms=31.339 node=client flow=10.1.0.178:37482-10.1.2.143:8080
metric=fct value_ms=161.896 node=client flow=10.1.0.178:37482-10.1.2.143:8080
metric=send_unlock value_ms=30.954 node=client flow=10.1.0.178:37494-10.1.2.143:8080
metric=fct value_ms=209.467 node=client flow=10.1.0.178:37494-10.1.2.143:8080
metric=send_unlock value_ms=28.013 node=client flow=10.1.0.178:37496-10.1.2.143:8080
metric=fct value_ms=200.526 node=client flow=10.1.0.178:37496-10.1.2.143:8080
metric=send_unlock value_ms=25.423 node=client flow=10.1.0.178:37504-10.1.2.143:8080
metric=fct value_ms=216.997 node=client flow=10.1.0.178:37504-10.1.2.143:8080
metric=send_unlock value_ms=24.756 node=client flow=10.1.0.178:37516-10.1.2.143:8080
metric=fct value_ms=118.994 node=client flow=10.1.0.178:37516-10.1.2.143:8080
metric=send_unlock value_ms=29.093 node=client flow=10.1.0.178:37520-10.1.2.143:8080
metric=fct value_ms=204.538 node=client flow=10.1.0.178:37520-10.1.2.143:8080
metric=send_unlock value_ms=28.423 node=client flow=10.1.0.178:37522-10.1.2.143:8080
metric=fct value_ms=149.189 node=client flow=10.1.0.178:37522-10.1.2.143:8080
metric=send_unlock value_ms=29.993 node=client flow=10.1.0.178:37532-10.1.2.143:8080
metric=fct value_ms=526.609 node=client flow=10.1.0.178:37532-10.1.2.143:8080
metric=send_unlock value_ms=23.518 node=client flow=10.1.0.178:37544-10.1.2.143:8080
metric=fct value_ms=117.383 node=client flow=10.1.0.178:37544-10.1.2.143:8080
metric=send_unlock value_ms=28.559 node=client flow=10.1.0.178:37560-10.1.2.143:8080
metric=fct value_ms=593.347 node=client flow=10.1.0.178:37560-10.1.2.143:8080
metric=send_unlock value_ms=25.375 node=client flow=10.1.0.178:37574-10.1.2.143:8080
metric=fct value_ms=116.845 node=client flow=10.1.0.178:37574-10.1.2.143:8080
metric=send_unlock value_ms=26.756 node=client flow=10.1.0.178:37578-10.1.2.143:8080
metric=fct value_ms=218.503 node=client flow=10.1.0.178:37578-10.1.2.143:8080
metric=send_unlock value_ms=22.130 node=client flow=10.1.0.178:37584-10.1.2.143:8080
metric=fct value_ms=156.994 node=client flow=10.1.0.178:37584-10.1.2.143:8080
metric=send_unlock value_ms=28.316 node=client flow=10.1.0.178:37600-10.1.2.143:8080
metric=fct value_ms=674.377 node=client flow=10.1.0.178:37600-10.1.2.143:8080
metric=send_unlock value_ms=27.936 node=client flow=10.1.0.178:37612-10.1.2.143:8080
metric=fct value_ms=531.116 node=client flow=10.1.0.178:37612-10.1.2.143:8080
metric=send_unlock value_ms=21.404 node=client flow=10.1.0.178:37622-10.1.2.143:8080
metric=fct value_ms=422.347 node=client flow=10.1.0.178:37622-10.1.2.143:8080
metric=send_unlock value_ms=26.956 node=client flow=10.1.0.178:37630-10.1.2.143:8080
metric=fct value_ms=590.108 node=client flow=10.1.0.178:37630-10.1.2.143:8080
metric=send_unlock value_ms=22.587 node=client flow=10.1.0.178:37632-10.1.2.143:8080
metric=fct value_ms=442.920 node=client flow=10.1.0.178:37632-10.1.2.143:8080
metric=send_unlock value_ms=26.476 node=client flow=10.1.0.178:37648-10.1.2.143:8080
metric=fct value_ms=360.346 node=client flow=10.1.0.178:37648-10.1.2.143:8080
metric=send_unlock value_ms=23.408 node=client flow=10.1.0.178:37652-10.1.2.143:8080
metric=fct value_ms=627.290 node=client flow=10.1.0.178:37652-10.1.2.143:8080
metric=send_unlock value_ms=23.279 node=client flow=10.1.0.178:37658-10.1.2.143:8080
metric=fct value_ms=421.274 node=client flow=10.1.0.178:37658-10.1.2.143:8080
metric=send_unlock value_ms=25.411 node=client flow=10.1.0.178:37664-10.1.2.143:8080
metric=fct value_ms=484.444 node=client flow=10.1.0.178:37664-10.1.2.143:8080
metric=send_unlock value_ms=20.702 node=client flow=10.1.0.178:37672-10.1.2.143:8080
metric=fct value_ms=360.577 node=client flow=10.1.0.178:37672-10.1.2.143:8080
metric=send_unlock value_ms=23.454 node=client flow=10.1.0.178:37676-10.1.2.143:8080
metric=fct value_ms=399.328 node=client flow=10.1.0.178:37676-10.1.2.143:8080
metric=send_unlock value_ms=22.483 node=client flow=10.1.0.178:37682-10.1.2.143:8080
metric=fct value_ms=548.339 node=client flow=10.1.0.178:37682-10.1.2.143:8080
metric=send_unlock value_ms=22.459 node=client flow=10.1.0.178:37688-10.1.2.143:8080
metric=fct value_ms=567.038 node=client flow=10.1.0.178:37688-10.1.2.143:8080
metric=send_unlock value_ms=21.760 node=client flow=10.1.0.178:37692-10.1.2.143:8080
metric=fct value_ms=482.414 node=client flow=10.1.0.178:37692-10.1.2.143:8080
metric=send_unlock value_ms=21.985 node=client flow=10.1.0.178:37694-10.1.2.143:8080
metric=fct value_ms=545.216 node=client flow=10.1.0.178:37694-10.1.2.143:8080
metric=send_unlock value_ms=21.288 node=client flow=10.1.0.178:37696-10.1.2.143:8080
metric=fct value_ms=499.949 node=client flow=10.1.0.178:37696-10.1.2.143:8080
metric=send_unlock value_ms=21.278 node=client flow=10.1.0.178:37706-10.1.2.143:8080
metric=fct value_ms=624.650 node=client flow=10.1.0.178:37706-10.1.2.143:8080
metric=send_unlock value_ms=21.604 node=client flow=10.1.0.178:37722-10.1.2.143:8080
metric=fct value_ms=361.317 node=client flow=10.1.0.178:37722-10.1.2.143:8080
metric=send_unlock value_ms=22.619 node=client flow=10.1.0.178:37726-10.1.2.143:8080
metric=fct value_ms=578.902 node=client flow=10.1.0.178:37726-10.1.2.143:8080
metric=send_unlock value_ms=17.936 node=client flow=10.1.0.178:37742-10.1.2.143:8080
metric=fct value_ms=545.196 node=client flow=10.1.0.178:37742-10.1.2.143:8080
metric=send_unlock value_ms=18.673 node=client flow=10.1.0.178:37756-10.1.2.143:8080
metric=fct value_ms=525.957 node=client flow=10.1.0.178:37756-10.1.2.143:8080
metric=send_unlock value_ms=20.087 node=client flow=10.1.0.178:37758-10.1.2.143:8080
metric=fct value_ms=584.948 node=client flow=10.1.0.178:37758-10.1.2.143:8080
metric=send_unlock value_ms=14.903 node=client flow=10.1.0.178:37764-10.1.2.143:8080
metric=fct value_ms=584.275 node=client flow=10.1.0.178:37764-10.1.2.143:8080
metric=send_unlock value_ms=20.816 node=client flow=10.1.0.178:37780-10.1.2.143:8080
metric=fct value_ms=646.570 node=client flow=10.1.0.178:37780-10.1.2.143:8080
metric=send_unlock value_ms=14.314 node=client flow=10.1.0.178:37794-10.1.2.143:8080
metric=fct value_ms=542.037 node=client flow=10.1.0.178:37794-10.1.2.143:8080
metric=send_unlock value_ms=14.463 node=client flow=10.1.0.178:37798-10.1.2.143:8080
metric=fct value_ms=562.457 node=client flow=10.1.0.178:37798-10.1.2.143:8080
metric=send_unlock value_ms=20.043 node=client flow=10.1.0.178:37812-10.1.2.143:8080
metric=fct value_ms=645.570 node=client flow=10.1.0.178:37812-10.1.2.143:8080
metric=send_unlock value_ms=12.181 node=client flow=10.1.0.178:37824-10.1.2.143:8080
metric=fct value_ms=582.788 node=client flow=10.1.0.178:37824-10.1.2.143:8080
metric=send_unlock value_ms=17.567 node=client flow=10.1.0.178:37826-10.1.2.143:8080
metric=fct value_ms=508.544 node=client flow=10.1.0.178:37826-10.1.2.143:8080
metric=send_unlock value_ms=17.135 node=client flow=10.1.0.178:37828-10.1.2.143:8080
metric=fct value_ms=643.596 node=client flow=10.1.0.178:37828-10.1.2.143:8080
metric=send_unlock value_ms=14.543 node=client flow=10.1.0.178:37838-10.1.2.143:8080
metric=fct value_ms=581.804 node=client flow=10.1.0.178:37838-10.1.2.143:8080
metric=send_unlock value_ms=13.233 node=client flow=10.1.0.178:37844-10.1.2.143:8080
metric=fct value_ms=581.482 node=client flow=10.1.0.178:37844-10.1.2.143:8080
metric=send_unlock value_ms=12.723 node=client flow=10.1.0.178:37848-10.1.2.143:8080
metric=fct value_ms=564.788 node=client flow=10.1.0.178:37848-10.1.2.143:8080
metric=send_unlock value_ms=11.948 node=client flow=10.1.0.178:37854-10.1.2.143:8080
metric=fct value_ms=411.837 node=client flow=10.1.0.178:37854-10.1.2.143:8080
metric=send_unlock value_ms=15.790 node=client flow=10.1.0.178:37868-10.1.2.143:8080
metric=fct value_ms=618.116 node=client flow=10.1.0.178:37868-10.1.2.143:8080
metric=send_unlock value_ms=12.046 node=client flow=10.1.0.178:37884-10.1.2.143:8080
metric=fct value_ms=475.057 node=client flow=10.1.0.178:37884-10.1.2.143:8080
metric=send_unlock value_ms=14.425 node=client flow=10.1.0.178:37892-10.1.2.143:8080
metric=fct value_ms=545.378 node=client flow=10.1.0.178:37892-10.1.2.143:8080
metric=send_unlock value_ms=12.831 node=client flow=10.1.0.178:37908-10.1.2.143:8080
metric=fct value_ms=392.492 node=client flow=10.1.0.178:37908-10.1.2.143:8080
metric=send_unlock value_ms=10.917 node=client flow=10.1.0.178:37916-10.1.2.143:8080
metric=fct value_ms=616.844 node=client flow=10.1.0.178:37916-10.1.2.143:8080
metric=send_unlock value_ms=14.072 node=client flow=10.1.0.178:37930-10.1.2.143:8080
metric=fct value_ms=389.838 node=client flow=10.1.0.178:37930-10.1.2.143:8080
metric=send_unlock value_ms=13.040 node=client flow=10.1.0.178:37932-10.1.2.143:8080
metric=fct value_ms=616.132 node=client flow=10.1.0.178:37932-10.1.2.143:8080
metric=send_unlock value_ms=10.295 node=client flow=10.1.0.178:37940-10.1.2.143:8080
metric=fct value_ms=519.320 node=client flow=10.1.0.178:37940-10.1.2.143:8080
metric=send_unlock value_ms=11.074 node=client flow=10.1.0.178:37956-10.1.2.143:8080
metric=fct value_ms=469.097 node=client flow=10.1.0.178:37956-10.1.2.143:8080
metric=send_unlock value_ms=12.343 node=client flow=10.1.0.178:37966-10.1.2.143:8080
metric=fct value_ms=456.041 node=client flow=10.1.0.178:37966-10.1.2.143:8080
metric=send_unlock value_ms=12.291 node=client flow=10.1.0.178:37980-10.1.2.143:8080
metric=fct value_ms=614.680 node=client flow=10.1.0.178:37980-10.1.2.143:8080
metric=send_unlock value_ms=6.525 node=client flow=10.1.0.178:37986-10.1.2.143:8080
metric=fct value_ms=559.978 node=client flow=10.1.0.178:37986-10.1.2.143:8080
metric=send_unlock value_ms=6.174 node=client flow=10.1.0.178:37998-10.1.2.143:8080
metric=fct value_ms=575.805 node=client flow=10.1.0.178:37998-10.1.2.143:8080
metric=send_unlock value_ms=11.776 node=client flow=10.1.0.178:38008-10.1.2.143:8080
metric=fct value_ms=637.855 node=client flow=10.1.0.178:38008-10.1.2.143:8080
metric=send_unlock value_ms=10.591 node=client flow=10.1.0.178:38012-10.1.2.143:8080
metric=fct value_ms=612.718 node=client flow=10.1.0.178:38012-10.1.2.143:8080
metric=send_unlock value_ms=9.835 node=client flow=10.1.0.178:38014-10.1.2.143:8080
metric=fct value_ms=612.879 node=client flow=10.1.0.178:38014-10.1.2.143:8080
metric=send_unlock value_ms=7.610 node=client flow=10.1.0.178:38030-10.1.2.143:8080
metric=fct value_ms=612.104 node=client flow=10.1.0.178:38030-10.1.2.143:8080
metric=send_unlock value_ms=9.496 node=client flow=10.1.0.178:38036-10.1.2.143:8080
metric=fct value_ms=611.954 node=client flow=10.1.0.178:38036-10.1.2.143:8080
metric=send_unlock value_ms=5.198 node=client flow=10.1.0.178:38052-10.1.2.143:8080
metric=fct value_ms=533.467 node=client flow=10.1.0.178:38052-10.1.2.143:8080
metric=send_unlock value_ms=8.227 node=client flow=10.1.0.178:38064-10.1.2.143:8080
metric=fct value_ms=573.515 node=client flow=10.1.0.178:38064-10.1.2.143:8080
metric=send_unlock value_ms=9.218 node=client flow=10.1.0.178:38078-10.1.2.143:8080
metric=fct value_ms=572.858 node=client flow=10.1.0.178:38078-10.1.2.143:8080
metric=send_unlock value_ms=8.632 node=client flow=10.1.0.178:38086-10.1.2.143:8080
metric=fct value_ms=609.813 node=client flow=10.1.0.178:38086-10.1.2.143:8080
metric=send_unlock value_ms=8.539 node=client flow=10.1.0.178:38096-10.1.2.143:8080
metric=fct value_ms=609.318 node=client flow=10.1.0.178:38096-10.1.2.143:8080
metric=send_unlock value_ms=1.699 node=client flow=10.1.0.178:38098-10.1.2.143:8080
metric=fct value_ms=529.373 node=client flow=10.1.0.178:38098-10.1.2.143:8080
metric=server_gap value_ms=36.110 node=server flow=10.1.0.178:37188-10.1.2.143:8080
metric=server_gap value_ms=35.939 node=server flow=10.1.0.178:37158-10.1.2.143:8080
metric=server_gap value_ms=36.177 node=server flow=10.1.0.178:37174-10.1.2.143:8080
metric=server_gap value_ms=35.618 node=server flow=10.1.0.178:37198-10.1.2.143:8080
metric=server_gap value_ms=35.099 node=server flow=10.1.0.178:37208-10.1.2.143:8080
metric=server_gap value_ms=34.457 node=server flow=10.1.0.178:37210-10.1.2.143:8080
metric=server_gap value_ms=34.289 node=server flow=10.1.0.178:37220-10.1.2.143:8080
metric=server_gap value_ms=33.944 node=server flow=10.1.0.178:37236-10.1.2.143:8080
metric=server_gap value_ms=36.134 node=server flow=10.1.0.178:37252-10.1.2.143:8080
metric=server_gap value_ms=33.319 node=server flow=10.1.0.178:37268-10.1.2.143:8080
metric=server_gap value_ms=35.849 node=server flow=10.1.0.178:37280-10.1.2.143:8080
metric=server_gap value_ms=35.974 node=server flow=10.1.0.178:37286-10.1.2.143:8080
metric=server_gap value_ms=35.254 node=server flow=10.1.0.178:37302-10.1.2.143:8080
metric=server_gap value_ms=32.244 node=server flow=10.1.0.178:37312-10.1.2.143:8080
metric=server_gap value_ms=35.094 node=server flow=10.1.0.178:37314-10.1.2.143:8080
metric=server_gap value_ms=31.614 node=server flow=10.1.0.178:37330-10.1.2.143:8080
metric=server_gap value_ms=31.274 node=server flow=10.1.0.178:37344-10.1.2.143:8080
metric=server_gap value_ms=35.135 node=server flow=10.1.0.178:37358-10.1.2.143:8080
metric=server_gap value_ms=35.207 node=server flow=10.1.0.178:37368-10.1.2.143:8080
metric=server_gap value_ms=35.235 node=server flow=10.1.0.178:37384-10.1.2.143:8080
metric=server_gap value_ms=30.249 node=server flow=10.1.0.178:37398-10.1.2.143:8080
metric=server_gap value_ms=36.928 node=server flow=10.1.0.178:37408-10.1.2.143:8080
metric=server_gap value_ms=28.962 node=server flow=10.1.0.178:37410-10.1.2.143:8080
metric=server_gap value_ms=28.960 node=server flow=10.1.0.178:37424-10.1.2.143:8080
metric=server_gap value_ms=28.492 node=server flow=10.1.0.178:37432-10.1.2.143:8080
metric=server_gap value_ms=34.866 node=server flow=10.1.0.178:37438-10.1.2.143:8080
metric=server_gap value_ms=27.680 node=server flow=10.1.0.178:37452-10.1.2.143:8080
metric=server_gap value_ms=39.919 node=server flow=10.1.0.178:37468-10.1.2.143:8080
metric=server_gap value_ms=27.055 node=server flow=10.1.0.178:37474-10.1.2.143:8080
metric=server_gap value_ms=36.762 node=server flow=10.1.0.178:37482-10.1.2.143:8080
metric=server_gap value_ms=36.771 node=server flow=10.1.0.178:37494-10.1.2.143:8080
metric=server_gap value_ms=31.450 node=server flow=10.1.0.178:37496-10.1.2.143:8080
metric=server_gap value_ms=25.869 node=server flow=10.1.0.178:37504-10.1.2.143:8080
metric=server_gap value_ms=25.191 node=server flow=10.1.0.178:37516-10.1.2.143:8080
metric=server_gap value_ms=34.134 node=server flow=10.1.0.178:37520-10.1.2.143:8080
metric=server_gap value_ms=33.457 node=server flow=10.1.0.178:37522-10.1.2.143:8080
metric=server_gap value_ms=36.442 node=server flow=10.1.0.178:37532-10.1.2.143:8080
metric=server_gap value_ms=24.082 node=server flow=10.1.0.178:37544-10.1.2.143:8080
metric=server_gap value_ms=34.736 node=server flow=10.1.0.178:37560-10.1.2.143:8080
metric=server_gap value_ms=29.001 node=server flow=10.1.0.178:37574-10.1.2.143:8080
metric=server_gap value_ms=31.276 node=server flow=10.1.0.178:37578-10.1.2.143:8080
metric=server_gap value_ms=22.938 node=server flow=10.1.0.178:37584-10.1.2.143:8080
metric=server_gap value_ms=257.675 node=server flow=10.1.0.178:37600-10.1.2.143:8080
metric=server_gap value_ms=34.603 node=server flow=10.1.0.178:37612-10.1.2.143:8080
metric=server_gap value_ms=22.464 node=server flow=10.1.0.178:37622-10.1.2.143:8080
metric=server_gap value_ms=234.271 node=server flow=10.1.0.178:37630-10.1.2.143:8080
metric=server_gap value_ms=25.782 node=server flow=10.1.0.178:37632-10.1.2.143:8080
metric=server_gap value_ms=33.003 node=server flow=10.1.0.178:37648-10.1.2.143:8080
metric=server_gap value_ms=27.756 node=server flow=10.1.0.178:37652-10.1.2.143:8080
metric=server_gap value_ms=27.771 node=server flow=10.1.0.178:37658-10.1.2.143:8080
metric=server_gap value_ms=254.849 node=server flow=10.1.0.178:37664-10.1.2.143:8080
metric=server_gap value_ms=23.294 node=server flow=10.1.0.178:37672-10.1.2.143:8080
metric=server_gap value_ms=29.154 node=server flow=10.1.0.178:37676-10.1.2.143:8080
metric=server_gap value_ms=27.183 node=server flow=10.1.0.178:37682-10.1.2.143:8080
metric=server_gap value_ms=27.745 node=server flow=10.1.0.178:37688-10.1.2.143:8080
metric=server_gap value_ms=26.425 node=server flow=10.1.0.178:37692-10.1.2.143:8080
metric=server_gap value_ms=27.431 node=server flow=10.1.0.178:37694-10.1.2.143:8080
metric=server_gap value_ms=26.525 node=server flow=10.1.0.178:37696-10.1.2.143:8080
metric=server_gap value_ms=26.707 node=server flow=10.1.0.178:37706-10.1.2.143:8080
metric=server_gap value_ms=28.122 node=server flow=10.1.0.178:37722-10.1.2.143:8080
metric=server_gap value_ms=29.049 node=server flow=10.1.0.178:37726-10.1.2.143:8080
metric=server_gap value_ms=21.494 node=server flow=10.1.0.178:37742-10.1.2.143:8080
metric=server_gap value_ms=22.802 node=server flow=10.1.0.178:37756-10.1.2.143:8080
metric=server_gap value_ms=26.353 node=server flow=10.1.0.178:37758-10.1.2.143:8080
metric=server_gap value_ms=15.946 node=server flow=10.1.0.178:37764-10.1.2.143:8080
metric=server_gap value_ms=27.403 node=server flow=10.1.0.178:37780-10.1.2.143:8080
metric=server_gap value_ms=15.526 node=server flow=10.1.0.178:37794-10.1.2.143:8080
metric=server_gap value_ms=16.102 node=server flow=10.1.0.178:37798-10.1.2.143:8080
metric=server_gap value_ms=26.935 node=server flow=10.1.0.178:37812-10.1.2.143:8080
metric=server_gap value_ms=12.189 node=server flow=10.1.0.178:37824-10.1.2.143:8080
metric=server_gap value_ms=23.681 node=server flow=10.1.0.178:37826-10.1.2.143:8080
metric=server_gap value_ms=23.150 node=server flow=10.1.0.178:37828-10.1.2.143:8080
metric=server_gap value_ms=18.378 node=server flow=10.1.0.178:37838-10.1.2.143:8080
metric=server_gap value_ms=15.970 node=server flow=10.1.0.178:37844-10.1.2.143:8080
metric=server_gap value_ms=15.048 node=server flow=10.1.0.178:37848-10.1.2.143:8080
metric=server_gap value_ms=13.634 node=server flow=10.1.0.178:37854-10.1.2.143:8080
metric=server_gap value_ms=22.316 node=server flow=10.1.0.178:37868-10.1.2.143:8080
metric=server_gap value_ms=14.718 node=server flow=10.1.0.178:37884-10.1.2.143:8080
metric=server_gap value_ms=20.228 node=server flow=10.1.0.178:37892-10.1.2.143:8080
metric=server_gap value_ms=16.874 node=server flow=10.1.0.178:37908-10.1.2.143:8080
metric=server_gap value_ms=13.758 node=server flow=10.1.0.178:37916-10.1.2.143:8080
metric=server_gap value_ms=20.344 node=server flow=10.1.0.178:37930-10.1.2.143:8080
metric=server_gap value_ms=18.629 node=server flow=10.1.0.178:37932-10.1.2.143:8080
metric=server_gap value_ms=13.375 node=server flow=10.1.0.178:37940-10.1.2.143:8080
metric=server_gap value_ms=15.127 node=server flow=10.1.0.178:37956-10.1.2.143:8080
metric=server_gap value_ms=17.850 node=server flow=10.1.0.178:37966-10.1.2.143:8080
metric=server_gap value_ms=18.646 node=server flow=10.1.0.178:37980-10.1.2.143:8080
metric=server_gap value_ms=7.677 node=server flow=10.1.0.178:37986-10.1.2.143:8080
metric=server_gap value_ms=7.176 node=server flow=10.1.0.178:37998-10.1.2.143:8080
metric=server_gap value_ms=18.571 node=server flow=10.1.0.178:38008-10.1.2.143:8080
metric=server_gap value_ms=218.574 node=server flow=10.1.0.178:38012-10.1.2.143:8080
metric=server_gap value_ms=15.857 node=server flow=10.1.0.178:38014-10.1.2.143:8080
metric=server_gap value_ms=11.461 node=server flow=10.1.0.178:38030-10.1.2.143:8080
metric=server_gap value_ms=15.908 node=server flow=10.1.0.178:38036-10.1.2.143:8080
metric=server_gap value_ms=7.413 node=server flow=10.1.0.178:38052-10.1.2.143:8080
metric=server_gap value_ms=14.105 node=server flow=10.1.0.178:38064-10.1.2.143:8080
metric=server_gap value_ms=15.637 node=server flow=10.1.0.178:38078-10.1.2.143:8080
metric=server_gap value_ms=15.392 node=server flow=10.1.0.178:38086-10.1.2.143:8080
metric=server_gap value_ms=215.187 node=server flow=10.1.0.178:38096-10.1.2.143:8080
metric=server_gap value_ms=3.128 node=server flow=10.1.0.178:38098-10.1.2.143:8080
```
