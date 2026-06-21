# DPDK Unit Tests

Smoke tests for the `clientnic-dpdk` binary using virtual PMDs (no ENA hardware required).

## What it tests

| Test | What it validates |
|------|-------------------|
| Binary validation | ELF format, DPDK library linkage |
| EAL init (null PMD) | DPDK initialization path works |
| Ring PMD | Software ring buffer devices created |
| No-device handling | Graceful error when no ports |
| Port enumeration | Port discovery with virtual devices |

All 5 tests use `net_null` / `net_ring` virtual PMDs and run on the ClientNIC VM where DPDK 23.11, hugepages, and the correct kernel are already present.

## Prerequisites

- ClientNIC VM running (tagged `smartnics-clientnic`)
- aws CLI configured with SSM access
- `~/zero-rtt-demo` on the VM is up to date (`git pull`)

## How to run

```bash
./experiments/dpdk/run_dpdk_tests_ssm.sh
```

The script:
1. Discovers the `smartnics-clientnic` instance by EC2 tag — exits with error if not found
2. Builds `clientnic-dpdk` on the VM via `meson setup builddir && ninja -C builddir` (timeout: 120s)
3. Runs `sudo bash clientnic/dpdk/tests/run_dpdk_tests.sh builddir/clientnic-dpdk` (timeout: 60s)
4. Exits 0 if all pass, non-zero if build or tests fail

## How to interpret results

Normal passing output looks like:

```
=== ClientNIC DPDK Test Suite ===

--- Test 1: Binary Validation ---
✓ PASS: Binary is valid ELF
✓ PASS: DPDK libraries linked

--- Test 2: DPDK EAL Init (null PMD) ---
✓ PASS: DPDK EAL initialized with null PMD

--- Test 3: DPDK Ring PMD ---
✓ PASS: Ring PMD devices created

--- Test 4: Graceful No-Device Handling ---
✓ PASS: Graceful handling when no DPDK ports available

--- Test 5: Port Enumeration ---
✓ PASS: Port enumeration output detected

=== Results: 5 passed, 0 failed, 0 skipped (of 5) ===
```

**SKIP** on tests 4–5 is acceptable — it means `--help` or port output isn't implemented yet, not a failure.

**FAIL** on tests 1–2 usually means the binary didn't build correctly or DPDK libraries aren't found.

## Relationship to the integration experiment

These unit tests run against virtual PMDs and don't require the full 4-VM chain. They validate the binary compiles and DPDK EAL initializes correctly. To test actual 0-RTT behavior with the ENA PMD, use `run_experiment.sh` (DPDK variant) instead.
