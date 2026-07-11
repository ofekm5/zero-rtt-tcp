# Build notes — sprint 5 round 1

## Changes made
- `src/clientnic/dpdk-forwarder/README.md` — added "Dual-DPDK data plane" section (eth0 mgmt/eth1/eth2 layout), updated `io.c/h` table row (was "eth0 AF_PACKET socket + eth1 DPDK ENA port"), updated Run section to include the required `--client-mac` flag
- `src/servernic/dpdk/README.md` — updated ENI layout section to reflect eth2 (Server-facing) now on DPDK ENA PMD instead of AF_PACKET, added management-ENI note, updated `io.c/h` table row
- `CLAUDE.md:9-14` — added a line under the AWS EC2 VMs platform bullet describing the dual-DPDK data plane and dedicated management ENI

No test files required changes: `src/clientnic/dpdk-forwarder/tests` and `src/servernic/dpdk/tests` already assert peer-MAC framing (`client_mac`/`server_mac`) and contain no AF_PACKET-specific assertions (raw socket fds, `SO_*BUFFORCE`, `sendto`/`recvfrom` mocking) — tasks 5.1 was already satisfied by prior sprints' work, verified via C1/C2 below rather than edited.

## Verification commands run
- C1: `python3 -m pytest src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests -q` — exit 0, "Pytest: 26 passed"
- C2: `! grep -rlE "AF_PACKET|SOCK_RAW|SO_RCVBUFFORCE|SO_SNDBUFFORCE" src/clientnic/dpdk-forwarder/tests src/servernic/dpdk/tests | grep -q .` — exit 0, no matches found
- C3: `grep -qE "client-mac|dual.DPDK|management ENI" src/clientnic/dpdk-forwarder/README.md src/servernic/dpdk/README.md` — exit 0, match found

## Open concerns
- `infra/dpdk/ARCHITECTURE.md` still describes the pre-sprint-3 2-ENI layout (no dedicated management ENI, eth1 shown as the only DPDK port). It's not referenced by any sprint-5 acceptance criterion and editing it is not authorized by this contract's scope (docs-only, READMEs + CLAUDE.md), so it was left untouched — flagging in case a future sprint should reconcile it against the actual `infra/dpdk/cdk/smartnics_stack.py` 3-ENI layout.
