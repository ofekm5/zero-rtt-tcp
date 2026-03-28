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

**Recommended: run via SSM on the ClientNIC VM** (handles build + test in one step):

```bash
./experiments/zero-rtt-dpdk/run_dpdk_tests_ssm.sh
```

This discovers the running `smartnics-clientnic` EC2 instance, builds the binary with meson/ninja, and runs the tests — no SSH key required. See the script for prerequisites (aws CLI, python3, ClientNIC VM running).

**Manual: run directly on the ClientNIC VM** (after SSH or SSM session):

```bash
# Build the binary first
export PKG_CONFIG_PATH=/usr/local/lib64/pkgconfig
cd ~/zero-rtt-demo/clientnic/dpdk
meson setup builddir && ninja -C builddir

# Run tests (requires root for EAL)
sudo ./tests/run_dpdk_tests.sh builddir/clientnic-dpdk
```

## Prerequisites

- ClientNIC VM running with DPDK 23.11 installed (provisioned by CDK)
- aws CLI configured with SSM access (for the SSM runner)
- Falls back to `--no-huge` if hugepages unavailable
