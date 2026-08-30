---
type: Raw Source
title: "Baseline TCP Report — 2026-05-31"
description: "Mode: Plain TCP (no 0-RTT middleware)"
tags: [experiments, baseline, archive]
timestamp: 2026-06-06T15:24:48+03:00
---

# Baseline TCP Report — 2026-05-31

**Mode**: Plain TCP (no 0-RTT middleware)
**Infra**: AWS `infra/dpdk` CDK stack — 4-VM chain, kernel forwarding on NIC VMs
**Connections**: 20 sequential
**Overall result**: 2 FAILURE(S) ❌

## TTFB Measurements

```
=== Repeated Connection Test (20 connections) ===
Server: 10.1.2.77:8080


Results:
  Success: 0/20 (0%)
```

## Server Log

```
[1;33m[19:36:02] Killing any leftover server.py...[0m
[1;33m[19:36:03] Pulling latest code...[0m
From https://github.com/ofekm5/zero-rtt-demo
 * branch            main       -> FETCH_HEAD
Already up to date.
[1;33m[19:36:03] Server VM IP: 10.1.2.77[0m
[1;33m[19:36:03] Will listen on 0.0.0.0:8080[0m

[1;33m[19:36:03] Starting server.py ? press Ctrl+C to stop.[0m

Server listening on 0.0.0.0:8080
```

## Notes

- NIC VMs (ClientNIC, ServerNIC) forwarded packets via kernel IP stack only
- eth1 rebound: vfio-pci → ena (before experiment) → vfio-pci (after experiment)
- Compare TTFB min/mean/p99 against `experiments/zero-rtt-dpdk/reports/` for 0-RTT benefit
