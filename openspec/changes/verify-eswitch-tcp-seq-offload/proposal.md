## Why

The BlueField-3 ARM cores (8× Cortex-A78AE) are slower at software packet processing than the x86 SmartNICs already in use, so moving the T8 translator onto the DPU as software is a performance regression, not a gain. The DPU is only worth deploying if the data path never touches an ARM core — which requires the e-switch to apply a per-flow ±delta to TCP sequence and acknowledgment numbers in hardware. That single capability is unverified, and every downstream architecture decision depends on the answer.

## Non-Goals

- **Implementing any part of the offloaded ServerNIC.** This change produces a verdict and the evidence behind it, not a data plane. The architecture lives in a separate change that is gated on this one.
- **Using DOCA Flow for the *primary* probe.** `testpmd`/`rte_flow` drives the first pass because it is interactive and needs no build cycle while the rule syntax is still unknown. A minimal DOCA Flow cross-check *is* in scope, but fires **only on a NO result** — see What Changes. Re-proving a *positive* result through DOCA Flow remains a follow-up.
- **Fixing lab DNS.** The DPU has raw-IP connectivity but no working resolver. The probe does not need one: `dpdk-testpmd` is preinstalled, and the DOCA devel container carrying `meson`/`ninja` is transported as a saved image rather than pulled.
- **Concurrent or at-scale flows.** One flow answers the capability question. Rule-install rate, flow-table capacity, and throughput are separate experiments.
- **Any performance or latency measurement.** This is a binary capability probe. A YES here says the hardware *can* do the rewrite, not how fast.
- **Fixing `run_core.sh`'s AWS assumptions** (`ec2-user`, `/usr/local/bin/meson`, `aws ec2 describe-instances`) or provisioning endpoint VMs. That is deployment work with its own change.
- **Anything touching the runs4 DPU** (`10.13.36.46`), which requires permission from another student.
- **Cabling `p0` or requesting a transceiver.** The spike deliberately runs over the `pf0hpf` path that exists today.
- **Modifying `src/servernic/dpdk/` or `src/clientnic/dpdk-forwarder/`.** No production source file is touched by this change.

## What Changes

- **New spike harness** under `experiments/bluefield/` that drives the whole probe end to end: records the pre-spike DPU baseline, allocates hugepages on the ARM, detaches `pf0hpf` from `ovsbr1`, launches `dpdk-testpmd`, installs a composed `rte_flow` rule, generates traffic from the x86 VM, captures the returned packets, and restores the DPU.
- **A composed `rte_flow` rule** exercising all three properties at once in the transfer domain: 5-tuple match, `modify_field` on `RTE_FLOW_FIELD_TCP_SEQ_NUM` / `TCP_ACK_NUM` with ADD/SUB, and hairpin egress back out `pf0hpf`.
- **Traffic generation and capture** driven from the x86 VM (`10.13.37.10`) over `ens16f0np0`, so the rewrite is observed on the wire rather than inferred from PMD return codes.
- **A conditional DOCA Flow cross-check** that runs **only when the `rte_flow` probe returns NO**. Both APIs drive the same mlx5 hardware steering but do not expose identical action sets, so a NO from `rte_flow` is ambiguous — it may be a silicon limit or merely an mlx5 PMD exposure gap. The cross-check distinguishes them before the architecture is abandoned. It is built inside the DOCA devel container, which ships `meson` and `ninja`, transported to the DPU as a saved image using the existing `infra/bluefield/deployment/compress_doca_image.sh` pattern — no DNS required.
- **A verdict document** recording YES / NO / PARTIAL with the captured evidence, the exact DPDK and firmware versions it was obtained on, the cross-check result when one was run, and what it implies for the companion architecture change.
- **Restore path** that returns `pf0hpf` to `ovsbr1` and frees hugepages, verified by diffing against the recorded baseline.

## Success Criteria

- [ ] Hugepages are allocated on the DPU ARM and `testpmd` binds `pf0hpf` as a DPDK port — measured by: `dpdk-testpmd` reaches the `testpmd>` prompt and `show port summary all` lists `pf0hpf`
- [ ] A single composed `rte_flow` rule — 5-tuple match, `modify_field` on TCP seq/ack, hairpin egress — is accepted by the mlx5 PMD in the transfer domain — measured by: `flow create … transfer …` returns a rule ID rather than an error
- [ ] The rule executes in hardware, not as a software fallback — measured by: `flow query <id> count` hits increment while testpmd's forwarding stats show zero packets crossing an ARM core
- [ ] Packets returning to the x86 VM carry the modified sequence number — measured by: `tcpdump` on `ens16f0np0` shows returned seq == sent seq ± the configured delta
- [ ] A verdict of YES / NO / PARTIAL is recorded with captured evidence, and the DPU is restored to its pre-spike state — measured by: manual review of the verdict document; `ovs-vsctl show` matches the recorded pre-spike baseline

## Capabilities

### New Capabilities

- `eswitch-offload-probe`: A reproducible procedure for determining whether the BlueField-3 e-switch can match a TCP flow, rewrite its sequence/acknowledgment numbers by a per-flow constant, and hairpin the packet back out the ingress port — entirely in hardware. Covers baseline capture, hugepage setup, rule composition, on-wire verification, verdict recording, and restoration of the DPU to its prior state.

### Modified Capabilities

<!-- None. No existing spec's requirements change; this adds a verification capability alongside them. -->

## Impact

- **New**: `experiments/bluefield/` — spike harness scripts and the verdict document. This directory does not exist yet.
- **Unchanged**: `src/servernic/dpdk/`, `src/clientnic/dpdk-forwarder/`, `experiments/utils/`, and all AWS infrastructure. No production source or existing experiment path is modified.
- **Lab state**: temporarily removes `pf0hpf` from `ovsbr1` on `bluefield-runs3-dpu` (`10.13.36.16`) and allocates hugepages on the ARM. Both are reverted by the restore path. The data path is currently idle — `p0` has no carrier and `ens16f0np0` is down — so nothing in use is displaced.
- **Hosts touched**: `10.13.36.16` (DPU ARM) and `10.13.37.10` (x86 host VM). Requires the RUNS lab OpenVPN tunnel and the existing `claude_code_ed25519` key access to both.
- **Downstream**: the companion architecture change is contingent on this verdict. A NO does not shrink that proposal — it invalidates it.

triage-verdict: ok
