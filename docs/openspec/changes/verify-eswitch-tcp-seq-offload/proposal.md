## Why

The BlueField-3 ARM cores (8× Cortex-A78AE) are slower at software packet processing than the x86 SmartNICs already in use, so moving the T8 translator onto the DPU as software is a performance regression, not a gain. The DPU is only worth deploying if the data path never touches an ARM core — which requires the e-switch to apply a per-flow ±delta to TCP sequence and acknowledgment numbers in hardware. That single capability is unverified, and every downstream architecture decision depends on the answer.

## Non-Goals

- **Implementing any part of the offloaded ServerNIC.** This change produces a verdict and the evidence behind it, not a data plane. The architecture lives in a separate change that is gated on this one.
- **Using `rte_flow`/`testpmd` for the *primary* probe.** DOCA Flow drives the first pass because it is the API most likely to ship — NVIDIA's recommended path for BF-3, with in-repo precedent in `infra/bluefield/examples/syn-punt/src/doca_flow_handler.c` — so a positive result proves the production path with no interpretation gap. A `testpmd`/`rte_flow` cross-check *is* in scope, but fires **only on a NO result** — see What Changes.
- **Fixing lab DNS.** The DPU has raw-IP connectivity but no working resolver, and does not need one: the DOCA devel container carrying `meson`/`ninja` is built on a machine that has DNS and transported as a saved image rather than pulled.
- **Interactive rule exploration as a deliverable.** The probe takes its rule parameters as CLI arguments so syntax can be iterated by re-running rather than rebuilding. Reproducing `testpmd`'s full interactive surface is not a goal.
- **Concurrent or at-scale flows.** One flow answers the capability question. Rule-install rate, flow-table capacity, and throughput are separate experiments.
- **Any performance or latency measurement.** This is a binary capability probe. A YES here says the hardware *can* do the rewrite, not how fast.
- **Fixing `run_core.sh`'s AWS assumptions** (`ec2-user`, `/usr/local/bin/meson`, `aws ec2 describe-instances`) or provisioning endpoint VMs. That is deployment work with its own change.
- **Anything touching the runs4 DPU** (`10.13.36.46`), which requires permission from another student.
- **Cabling `p0` or requesting a transceiver.** The spike deliberately runs over the `pf0hpf` path that exists today.
- **Modifying `src/servernic/dpdk/` or `src/clientnic/dpdk-forwarder/`.** No production source file is touched by this change.

## What Changes

- **New spike harness** under `experiments/bluefield/` that drives the whole probe end to end: records the pre-spike DPU baseline, allocates hugepages on the ARM, detaches `pf0hpf` from `ovsbr1`, runs the DOCA Flow probe, generates traffic from the x86 VM, captures the returned packets, and restores the DPU.
- **A minimal DOCA Flow probe program** exercising all three properties at once in the e-switch domain: 5-tuple match, TCP sequence-number modification by a per-flow constant, and egress back out `pf0hpf`, with a counter attached. Rule parameters are CLI arguments so syntax is iterated by re-running, not rebuilding.
- **Container build and offline transport** for that program, following the existing `infra/bluefield/deployment/Dockerfile` and `compress_doca_image.sh` pattern: built on a machine with DNS inside the DOCA devel container that ships `meson` and `ninja`, saved to a tarball, transferred and `docker load`ed on the DPU. No registry pull or DNS resolution from the DPU.
- **Traffic generation and capture** driven from the x86 VM (`10.13.37.10`) over `ens16f0np0`, so the rewrite is observed on the wire rather than inferred from API return codes.
- **A conditional `rte_flow` cross-check** via the preinstalled `dpdk-testpmd`, running **only when the DOCA Flow probe returns NO**. Both APIs drive the same mlx5 hardware steering but do not expose identical action sets, so a single API's rejection is ambiguous — it may be a silicon limit or merely that API's exposure gap. The cross-check distinguishes them before the architecture is abandoned, and costs nothing to attempt since `testpmd` is already on the DPU.
- **A verdict document** recording YES / NO / PARTIAL with the captured evidence, the exact DPDK and firmware versions it was obtained on, the cross-check result when one was run, and what it implies for the companion architecture change.
- **Restore path** that returns `pf0hpf` to `ovsbr1` and frees hugepages, verified by diffing against the recorded baseline.

## Success Criteria

- [ ] Hugepages are allocated on the DPU ARM and the probe initialises `pf0hpf` as a data-plane port — measured by: the probe's startup output reports `pf0hpf` initialised without error
- [ ] A single composed rule — 5-tuple match, TCP seq/ack modification, egress back toward the host port — is accepted in the transfer/e-switch domain — measured by: the rule-creation call returns a valid handle rather than an error
- [ ] The rule executes in hardware, not as a software fallback — measured by: the rule's hardware counter increments while the probe reports zero packets received on an ARM software queue
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
