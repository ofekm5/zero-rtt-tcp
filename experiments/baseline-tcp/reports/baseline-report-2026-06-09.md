# Baseline TCP Report — 2026-06-09

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: `infra/baseline` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding
**Connections**: 20 sequential
**Overall result**: ALL PASSED ✅

## Latency Summary (Client TTFB + FCT)

```
  Client TTFB: no samples found
  Client FCT : no samples found
```

## TTFB Measurements

```
--- Connection 1/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45734 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.00   sec  1.06 MBytes  2288 Mbits/sec    0    218 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.00   sec  1.06 MBytes  2288 Mbits/sec    0             sender
[  4]   0.00-0.00   sec   256 KBytes   540 Mbits/sec                  receiver

iperf Done.
--- Connection 2/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45754 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.00   sec  1.24 MBytes  2335 Mbits/sec    0    227 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.00   sec  1.24 MBytes  2335 Mbits/sec    0             sender
[  4]   0.00-0.00   sec   640 KBytes  1179 Mbits/sec                  receiver

iperf Done.
--- Connection 3/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45778 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.00   sec  1.06 MBytes  1939 Mbits/sec    0    184 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.00   sec  1.06 MBytes  1939 Mbits/sec    0             sender
[  4]   0.00-0.00   sec   640 KBytes  1145 Mbits/sec                  receiver

iperf Done.
--- Connection 4/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45806 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.00   sec  1.31 MBytes  2478 Mbits/sec    0    280 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.00   sec  1.31 MBytes  2478 Mbits/sec    0             sender
[  4]   0.00-0.00   sec   512 KBytes   949 Mbits/sec                  receiver

iperf Done.
--- Connection 5/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45826 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.19 MBytes  1399 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.19 MBytes  1399 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   885 Mbits/sec                  receiver

iperf Done.
--- Connection 6/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45850 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.25 MBytes  1572 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.25 MBytes  1572 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   946 Mbits/sec                  receiver

iperf Done.
--- Connection 7/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45878 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.24 MBytes  1379 Mbits/sec    0    166 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.24 MBytes  1379 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   836 Mbits/sec                  receiver

iperf Done.
--- Connection 8/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45884 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.42 MBytes  2075 Mbits/sec    0    315 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.42 MBytes  2075 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   512 KBytes   732 Mbits/sec                  receiver

iperf Done.
--- Connection 9/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45908 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.24 MBytes  1405 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.24 MBytes  1405 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   851 Mbits/sec                  receiver

iperf Done.
--- Connection 10/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45920 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.24 MBytes  1262 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.24 MBytes  1262 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   765 Mbits/sec                  receiver

iperf Done.
--- Connection 11/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45942 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.06 MBytes  1441 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.06 MBytes  1441 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   851 Mbits/sec                  receiver

iperf Done.
--- Connection 12/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45968 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.10 MBytes  1121 Mbits/sec    0    149 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.10 MBytes  1121 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   636 Mbits/sec                  receiver

iperf Done.
--- Connection 13/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45986 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.01 MBytes  1612 Mbits/sec    0    149 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.01 MBytes  1612 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   512 KBytes   800 Mbits/sec                  receiver

iperf Done.
--- Connection 14/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 45994 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.24 MBytes  1643 Mbits/sec    0    166 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.24 MBytes  1643 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   995 Mbits/sec                  receiver

iperf Done.
--- Connection 15/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46014 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.06 MBytes  1397 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.06 MBytes  1397 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   825 Mbits/sec                  receiver

iperf Done.
--- Connection 16/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46030 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.09 MBytes  1382 Mbits/sec    0    175 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.09 MBytes  1382 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   791 Mbits/sec                  receiver

iperf Done.
--- Connection 17/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46054 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.06 MBytes  1413 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.06 MBytes  1413 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   834 Mbits/sec                  receiver

iperf Done.
--- Connection 18/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46080 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.30 MBytes  1396 Mbits/sec    0    253 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.30 MBytes  1396 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   672 Mbits/sec                  receiver

iperf Done.
--- Connection 19/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46100 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.24 MBytes  1430 Mbits/sec    0    157 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.24 MBytes  1430 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   768 KBytes   866 Mbits/sec                  receiver

iperf Done.
--- Connection 20/20 ---
Connecting to host 10.1.2.74, port 8080
[  4] local 10.1.0.88 port 46126 connected to 10.1.2.74 port 8080
[ ID] Interval           Transfer     Bandwidth       Retr  Cwnd
[  4]   0.00-0.01   sec  1.36 MBytes  1597 Mbits/sec    0    297 KBytes       
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth       Retr
[  4]   0.00-0.01   sec  1.36 MBytes  1597 Mbits/sec    0             sender
[  4]   0.00-0.01   sec   640 KBytes   735 Mbits/sec                  receiver

iperf Done.
Success: 20/20
```

## Server Log

```
[  5]   0.00-0.05   sec   768 KBytes   130 Mbits/sec                  
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth
[  5]   0.00-0.05   sec  0.00 Bytes  0.00 bits/sec                  sender
[  5]   0.00-0.05   sec   768 KBytes   130 Mbits/sec                  receiver
-----------------------------------------------------------
Server listening on 8080
-----------------------------------------------------------
Accepted connection from 10.1.0.88, port 46116
[  5] local 10.1.2.74 port 8080 connected to 10.1.0.88 port 46126
[ ID] Interval           Transfer     Bandwidth
[  5]   0.00-0.05   sec   640 KBytes   109 Mbits/sec                  
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bandwidth
[  5]   0.00-0.05   sec  0.00 Bytes  0.00 bits/sec                  sender
[  5]   0.00-0.05   sec   640 KBytes   109 Mbits/sec                  receiver
-----------------------------------------------------------
Server listening on 8080
-----------------------------------------------------------
iperf3: interrupt - the server has terminated
```

## Notes

- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server
- ClientNIC: ip_forward=1, static route 10.1.2.0/24 via 10.1.1.1 dev eth1
- ServerNIC: ip_forward=1, static route 10.1.0.0/24 via 10.1.1.1 dev eth0
- Compare TTFB min/mean/p99 against experiments/zero-rtt-dpdk/reports/ for 0-RTT benefit
