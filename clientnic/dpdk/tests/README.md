# ClientNIC DPDK Tests

Local DPDK smoke tests imported from [wire-app](C:\Users\shir\Documents\GitHub\wire-app) GitLab CI pipeline, adapted for the clientnic-dpdk binary.

## What's tested

| Test | Source (wire-app) | Confidence | What it validates |
|------|-------------------|------------|-------------------|
| Binary validation | `test:binary_check` | High | ELF format, DPDK library linkage |
| EAL init (null PMD) | `dpdk:virtual_pmd_test` | 50% | DPDK initialization path works |
| Ring PMD | `dpdk:ring_pmd_test` | 55% | Software ring buffer devices created |
| No-device handling | `dpdk:integration_test` | 30% | Graceful error when no ports |
| Port enumeration | — | 40% | Port discovery with virtual devices |

All tests use **virtual PMDs** (`net_null`, `net_ring`) — no hardware or AWS deployment required.

## Usage

```bash
# Build the binary first
cd clientnic/dpdk
meson setup builddir
ninja -C builddir

# Run tests (requires root for EAL, or --no-huge fallback)
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk
```

## Prerequisites

- DPDK 23.11+ installed (`dpdk-dev`, `libdpdk-dev`)
- Linux (DPDK doesn't run on Windows)
- Root or hugepages configured (`echo 256 > /proc/sys/vm/nr_hugepages`)
- Falls back to `--no-huge` if hugepages unavailable

## CI Integration

These tests map to wire-app's GitLab CI stages. To add to a GitLab pipeline, see the test jobs in `wire-app/.gitlab-ci.yml` (`dpdk:virtual_pmd_test`, `dpdk:ring_pmd_test`, `dpdk:integration_test`).
