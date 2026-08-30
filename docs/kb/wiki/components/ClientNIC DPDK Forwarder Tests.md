---
type: Wiki Entry
title: "ClientNIC DPDK Forwarder Tests"
description: "DPDK virtual PMD smoke-test suite targeting the clientnic-dpdk-forwarder binary"
tags: [component, clientnic, dpdk, tests]
timestamp: 2026-07-09T09:05:48+03:00
---

Source: `src/clientnic/dpdk-forwarder/tests/README.md`

# ClientNIC DPDK Forwarder Tests

DPDK virtual PMD smoke-test suite targeting the `clientnic-dpdk-forwarder` binary
(no ENA hardware required).

## Usage

```bash
cd src/clientnic/dpdk-forwarder
meson setup builddir
ninja -C builddir
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk-forwarder
```
