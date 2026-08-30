## Why

The BlueField-3's 8× Cortex-A78AE cores are slower at software packet processing than the x86 SmartNICs already running the T8 data plane, so porting `src/servernic/dpdk/` to the ARM as-is would be a performance regression. The DPU earns its place only if post-handshake packets are matched and rewritten by the e-switch without a CPU in the path, leaving the ARM to handle the handshake alone.

## Non-Goals

- **Any change to ClientNIC.** It stays on x86, unchanged, still spoofing the SYN-ACK and stamping V in the SYN ack-num per the T8 contract. Moving ClientNIC onto a DPU is long-term work requiring the second BlueField.
- **Lab deployment plumbing.** Broken lab DNS, `run_core.sh`'s AWS assumptions (`ec2-user`, `/usr/local/bin/meson`, `aws ec2 describe-instances`), and endpoint VM provisioning all belong to a separate deployment change. Chosen deliberately during Socratic questioning over bundling them here. The **ARM build toolchain is explicitly *not* in that list** — the DOCA devel container ships `meson`/`ninja` and `infra/bluefield/deployment/compress_doca_image.sh` already scripts offline transport, so Success Criterion 1 is satisfiable within this change.
- **Committing to a specific offload API up front.** `rte_flow` was originally chosen partly on the incorrect premise that DOCA Flow was blocked by a missing ARM toolchain. That premise was wrong, so the API is treated as an **open decision** resolved after the spike reports which actions each API actually exposes on this card. `offload.c` keeps rule composition behind a backend boundary so either fits without disturbing the control plane.
- **Anything touching the runs4 DPU** (`10.13.36.46`) or any dual-BlueField topology. Requires permission from another student.
- **Cabling `p0` or requesting a transceiver.** The design deliberately works with `p0` dark, using the `pf0hpf` path that exists today.
- **100k-connection load testing, throughput, or latency measurement.** Separate experiments with their own success criteria.
- **Modifying `src/servernic/dpdk/`'s existing behaviour.** The AWS x86 path must keep working untouched; shared modules are reused, not rewritten.
- **Replacing software buffering of pre-delta packets.** Packets arriving before the delta is known cannot be covered by a hardware rule that does not yet exist, so that path stays in ARM software.

## What Changes

- **New meson target `src/servernic/bluefield/`** producing a DPU-side ServerNIC binary, reusing `flow_table.c`, `syn_handler.c`, and `checksum.c` from the existing tree rather than duplicating them.
- **New `io.c`** binding mlx5 representor ports on the DPU ARM in place of the ENA/AF_PACKET pair used on AWS.
- **New `offload.c`** owning per-flow hardware rule lifecycle: composing the transfer-domain rule from a flow's delta, installing it once the delta is known, and tearing it down on connection teardown. Rule composition and installation sit behind a narrow backend interface so the concrete API — `rte_flow` or DOCA Flow — is a swappable implementation rather than a structural commitment.
- **New `pipeline.c`** that classifies and dispatches handshake packets only — SYN, SYN-ACK, FIN, RST — since data packets never reach software.
- **Software translation confined to the pre-delta window.** `translator.c` is not carried over; the hardware rule performs all post-handshake rewriting, and buffered packets flushed at delta-computation time are rewritten in software once.
- **Flow teardown on FIN/RST** driving rule removal, so hardware rule count tracks live connections rather than accumulating.

## Success Criteria

- [ ] `src/servernic/bluefield/` builds on the DPU ARM against the installed DPDK — measured by: `meson setup builddir && ninja -C builddir` exits 0 on 10.13.36.16
- [ ] The ARM control plane extracts V from the SYN ack-num, computes the delta on SYN-ACK, and installs exactly one hardware rule set per flow — measured by: `flow list 0` on the DPU shows the expected rule count for N established connections
- [ ] Post-handshake data packets are rewritten in hardware and never reach an ARM core — measured by: rule counters increment while the application's software RX counter for non-handshake packets stays at zero
- [ ] A TCP connection through the DPU completes with correct sequence translation end to end — measured by: an iperf transfer completes without error and a capture confirms server→client SEQ carries the spoofed delta
- [ ] Per-flow rules are removed on connection teardown, with no accumulation across repeated connections — measured by: `flow list 0` returns to its pre-run rule count after N connections open and close

## Capabilities

### New Capabilities

- `bluefield-offload-control-plane`: ARM-side handling of the TCP handshake on the DPU — V extraction from the SYN ack-num, delta computation on the real SYN-ACK, software rewrite and flush of packets buffered before the delta was known, and the per-flow hardware rule lifecycle including teardown on FIN/RST.
- `bluefield-hw-translation`: The hardware data path — a transfer-domain rule set per flow that matches the connection's 5-tuple, applies the flow's delta to TCP sequence and acknowledgment numbers in the correct direction, and returns the packet without a CPU in the path. Specified against a backend interface so the concrete API (`rte_flow` or DOCA Flow) is an implementation choice resolved by the spike.

### Modified Capabilities

<!-- None. The existing x86 ServerNIC specs remain accurate for src/servernic/dpdk/, which this change does not alter. -->

## Impact

- **New**: `src/servernic/bluefield/` — `main.c`, `io.c`, `offload.c`, `pipeline.c`, `meson.build`, `README.md`, and tests. Reuses `flow_table.c`, `syn_handler.c`, `checksum.c` from `src/servernic/dpdk/` by reference.
- **Unchanged**: `src/servernic/dpdk/` behaviour and its AWS x86 deployment path; `src/clientnic/dpdk-forwarder/`; all AWS CDK infrastructure; every existing experiment orchestrator.
- **Target hardware**: `bluefield-runs3-dpu` (`10.13.36.16`) — BlueField-3 in `switchdev` / `EMBEDDED_CPU` mode, DOCA 3.0.0058, DPDK under `/opt/mellanox/dpdk`. `pf0hpf` is the sole data path; `p0` has no carrier and the card has no `p1`.
- **Blocking dependency**: `verify-eswitch-tcp-seq-offload` must not return NO. A NO — recorded only after that change's `rte_flow` cross-check confirms the silicon genuinely cannot do the rewrite — invalidates this change rather than reducing it. Its two PARTIAL branches are survivable: a failed return leg redirects egress to a Scalable Function, and a capability reachable only through `rte_flow` selects that backend behind `offload.c`'s interface.
- **Decision dependency**: the concrete offload API is resolved by the spike's findings, not assumed here. Both `## What Changes` and the specs are written against a backend interface for that reason.
- **Sequencing dependency**: Success Criterion 4 is only observable once the separate lab deployment change lands, since it requires a running client, server, and ClientNIC in the lab. Success Criterion 1 has no such dependency — the container toolchain path makes the ARM build self-contained.

triage-verdict: ok
