## Context

The ClientNIC DPDK app targets AWS ENA hardware on EC2. A Docker-based local test approach was attempted but abandoned because:
- Virtual PMDs (`net_null`, `net_ring`) don't exercise the ENA code path
- Docker requires `--privileged` + EAL hacks for a container environment
- The ClientNIC VM already has DPDK 23.11, hugepages, and the right kernel

The existing `run_experiment.sh` already establishes the pattern: discover instances by EC2 tag, run commands via `aws ssm send-command`, wait for completion, capture output. `run_dpdk_tests_ssm.sh` follows the same pattern.

The existing `run_dpdk_tests.sh` test script (5 smoke tests using virtual PMDs) stays unchanged — it runs fine on the VM.

## Goals / Non-Goals

**Goals:**
- Replace Docker-based test infra with an SSM-driven script that runs on the real ClientNIC VM
- Reuse `run_dpdk_tests.sh` unchanged — the test cases are good, only the execution environment changes
- Document the DPDK test flow in the zero-rtt-integration-tester skill
- Clean up Dockerfile and Docker wrapper

**Non-Goals:**
- Changing the DPDK test cases themselves
- Running tests against the real ENA PMD (tests still use virtual PMDs on the VM; ENA tests require a live 0-RTT session)
- CI/CD pipeline integration (out of scope)

## Decisions

### SSM over SSH
Consistent with the rest of the repo — no key management, works wherever `aws` CLI works, same approach as `run_experiment.sh`.

### Script location: `experiments/zero-rtt-clientnic-translate/`
Lives alongside `run_experiment.sh` rather than in `clientnic/dpdk/tests/` because it's an orchestration script that drives the VM from the outside, not a test script that runs inside the VM.

### Build on VM, not pre-built artifact upload
The VM has `meson`/`ninja` installed. Building on the VM ensures the binary matches the kernel/DPDK version there. Uploading a pre-built binary would require cross-compilation and file transfer.

### SSM timeout budget
- Build step: 120s (cold build ~30s, cached ~5s)
- Test run: 60s (all 5 tests complete in <10s)

## Risks / Trade-offs

- **VM must be running** → same constraint as `run_experiment.sh`; acceptable since both are manual developer workflows
- **Build noise in output** → ninja output mixed with test results; mitigated by section headers in the script
- **Repo must be synced on VM** → assumes `~/zero-rtt-demo` is up to date; same assumption as `run_experiment.sh`
