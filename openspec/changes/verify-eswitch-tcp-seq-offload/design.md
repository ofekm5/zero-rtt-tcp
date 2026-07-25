## Context

The `bluefield-runs3-dpu` (`10.13.36.16`) is a BlueField-3 in DPU mode (`INTERNAL_CPU_MODEL=EMBEDDED_CPU`), e-switch in `switchdev`, DOCA 3.0.0058 with `libdoca_flow`, DPDK under `/opt/mellanox/dpdk`. Its host is the Proxmox VM `bluefield-dev` (`10.13.37.10`), which owns the ConnectX-7 PF by PCIe passthrough and sees it as `ens16f0np0` (`mlx5_core`).

Three facts from live inspection constrain the design:

1. **`p0` is dark** — no carrier, no link partner, and this card has no `p1`. The only data path into the e-switch is `ens16f0np0` ↔ `pf0hpf`, which are two ends of one link, not two ports.
2. **The ARM host OS has no `meson`/`ninja`, and DNS is broken** (resolver `172.27.6.200` does not answer; raw-IP routing works). This is *not* a blocker for compiling: the DOCA devel container ships both tools, and the repo already scripts offline transport — `infra/bluefield/deployment/Dockerfile` builds `FROM nvcr.io/nvidia/doca/doca:2.9.3-devel` and runs `meson`/`ninja` inside it, while `compress_doca_image.sh` and `wire-example/build_wire_image.sh --save` produce a saved image tarball for `scp` + `docker load`. Compiling on the DPU costs a transport step, not a DNS fix.
3. **Management is independent of the data path** — the DPU is reached over `oob_net0`, a separate physical port. Taking `pf0hpf` away from `ovsbr1` cannot sever access to the DPU.

Fact 3 is what makes this spike safe to run; fact 1 is what shapes it into a single-port exercise. Fact 2 shapes only the *ordering* — the interactive `testpmd` pass runs first because it needs no build cycle, not because a build is impossible.

That last point is a correction to an earlier reading of this environment. `command -v meson` returning nothing on the ARM host OS was mistaken for "cannot compile here"; the container path was already present in the repo.

## Goals / Non-Goals

**Goals:**

- Produce a defensible YES / NO / PARTIAL verdict on whether the e-switch can match a TCP flow, rewrite seq/ack by a per-flow constant, and return the packet — all in hardware.
- Distinguish *rule accepted* from *rule offloaded* from *packet actually rewritten*. These are three different things and only the third is decisive.
- Make PARTIAL a meaningful outcome that maps to a concrete architectural fallback, not an inconclusive shrug.
- Leave the DPU byte-for-byte as it was found.

**Non-Goals:**

- Any throughput, latency, or rule-install-rate measurement.
- DOCA Flow verification (deliberate follow-up; see `proposal.md` Non-Goals).
- Multiple concurrent flows or flow-table capacity probing.
- Fixing the ARM toolchain or lab DNS beyond what the spike itself needs.

## Decisions

### D1 — Test in the transfer (e-switch) domain, not the NIC domain

The architecture depends on packets being steered and rewritten by the **e-switch**, so the spike must exercise the `transfer` attribute. A NIC-domain rule would prove a different, weaker thing: that the PMD can rewrite a packet on its way to a local queue, which says nothing about e-switch steering between vports.

The rule shape under test composes all three properties in one:

```
flow create 0 transfer ingress group 0
  pattern eth / ipv4 src is <client> dst is <server>
        / tcp  src is <sport> dst is <dport> / end
  actions modify_field op sub dst_type tcp_seq_num
                       src_type value src_value <delta> width 32
        / represented_port ethdev_port_id 0
        / count / end
```

`count` is attached deliberately — it is how SC3 distinguishes a hardware hit from a software fallback.

### D2 — Three-level verification, because rule acceptance is not evidence

`flow create` returning a rule ID means the PMD *validated* the rule, not that hardware executes it. The spike therefore checks three independent signals, in order:

| Level | Signal | What a failure here means |
|---|---|---|
| Accepted | `flow create` returns a rule ID | The action is not exposed by the mlx5 PMD — **ambiguous**, triggers the D6 cross-check |
| Offloaded | `flow query <id> count` hits increment **and** testpmd forwarding stats stay at zero | Rule matched but packets are crossing an ARM core — the design's premise fails |
| Effective | `tcpdump` on `ens16f0np0` shows `seq == sent ± delta` | Rule matched and counted but did not actually rewrite — a silent no-op |

All three must hold for YES. The third is the only one that cannot be faked by a permissive PMD.

### D6 — YES and NO are not symmetric, so a NO gets a DOCA Flow cross-check

DOCA Flow and `rte_flow` both compile down to the same mlx5 hardware steering, but they do not expose identical action sets. That makes the two outcomes asymmetric:

| Result | Interpretation | Consequence |
|---|---|---|
| **YES** | The silicon performs the rewrite. DOCA Flow, sitting on the same steering layer, almost certainly can too. | Decisive. No second stage runs. |
| **NO** | Either the silicon cannot do it, **or** the mlx5 PMD simply does not wire that action into `rte_flow`. | **Not decisive.** Run the cross-check. |

Abandoning the platform on an unqualified NO would risk discarding a working architecture over a PMD gap. So a NO — and only a NO — triggers a minimal DOCA Flow program that attempts the same TCP seq modification, built inside the DOCA devel container and transported per the Context fact 2 path.

The cross-check is deliberately scoped to the single question "does *any* API on this card expose a per-flow TCP seq/ack modify?" It is not a second full probe: no hairpin, no on-wire capture, no traffic generation. Its only job is to disambiguate the NO.

A YES from the cross-check after a NO from `rte_flow` is recorded as PARTIAL, not YES — the capability exists but the production API question is then materially different, which is why the companion change treats its offload API as an open decision rather than a settled one.

### D3 — Generate and capture from the x86 VM, not from testpmd

testpmd can generate its own traffic (`txonly`, `flowgen`), but then the sender, the rewriter, and the receiver are all the same process on the ARM — which cannot distinguish a hardware hairpin from testpmd forwarding a packet in software. Sending real TCP packets from `ens16f0np0` on the x86 VM and capturing on the same interface makes the round trip externally observable, and matches the target architecture's traffic direction.

### D4 — PARTIAL is a defined outcome with a defined consequence

Two sub-capabilities can fail independently, and they have different architectural implications:

- **Rewrite works, same-port return rejected** → e-switch split-horizon is blocking the return leg. The architecture survives by using a Scalable Function as the egress port instead of returning out `pf0hpf`. `mlxdevm` is present at `/opt/mellanox/iproute2/sbin/mlxdevm` and the e-switch is in `switchdev`, so SFs are creatable ARM-side without host or Proxmox involvement.
- **Rewrite rejected** → decisive NO regardless of what the return leg does. No topology change rescues it.

The verdict document must state which of these occurred, because the two lead to different next changes.

### D5 — Restore is a success criterion, not a cleanup step

The DPU is shared lab infrastructure. The baseline (`ovs-vsctl show`, hugepage count, `pf0hpf` bridge membership) is captured **before** any mutation and diffed after, and that diff is SC5. Treating restoration as an acceptance criterion rather than a trailing `cleanup()` is what prevents a half-restored DPU from being reported as a pass.

## Alternatives Considered

### A. `testpmd` / `rte_flow`, transfer domain, single port — **recommended**

Drive the composed rule interactively through the preinstalled `dpdk-testpmd`, generating traffic from the x86 VM over the existing `pf0hpf` link.

*Tradeoffs*: Zero code and no build cycle, which matters most while the rule syntax is still unknown — `represented_port` versus `port_id`, and whether `dv_flow_en=2` is required (the existing `infra/bluefield/deployment/Dockerfile` passes it). Interactive iteration is measured in seconds rather than edit-build-run cycles. Costs: `rte_flow` acceptance does not guarantee DOCA Flow exposes the identical action, and — more consequentially — a *rejection* does not prove the silicon lacks the capability. See D6.

*Verdict*: **Recommended as the primary probe**, paired with the D6 cross-check so its ambiguous negative does not become a wrong platform decision.

### B. Small DOCA Flow C program as the sole probe

Write a minimal DOCA Flow application that builds a pipe with a TCP seq/ack modify action, and use only that.

*Tradeoffs*: Removes the API interpretation gap in both directions, and matches the in-repo precedent — `infra/bluefield/examples/syn-punt/src/doca_flow_handler.c` already uses DOCA Flow. But it trades away the interactive iteration that is most valuable precisely when the rule syntax is unknown, and it front-loads a container build and transport before any answer exists.

*Verdict*: **Rejected as the sole probe, adopted as the conditional negative-path stage.** The earlier rejection of this option cited a missing ARM toolchain; that reasoning was wrong — the DOCA devel container ships `meson`/`ninja` and the repo already scripts offline transport. The option is rejected here on iteration speed and sequencing, not on feasibility.

### C. Two-port test using a Scalable Function as egress

Create an SF via `mlxdevm`, then test a transfer rule that matches on `pf0hpf` ingress, rewrites seq/ack, and forwards to the SF representor — capturing on the SF netdev on the ARM.

*Tradeoffs*: Sidesteps the same-port return question completely, so it isolates the rewrite capability cleanly, and its two-port shape is closer to today's `src/servernic/dpdk/` structure. But it changes what is being proven: it verifies rewrite plus vport-to-vport steering, not the return-to-host path the single-port architecture actually needs. It also adds SF lifecycle (create, configure, delete) to the spike's mutation surface and therefore to its restore burden.

*Verdict*: **On the shelf** — explicitly the fallback path when the spike lands on D4's first PARTIAL branch. Not the primary test, because proving the harder composed case first is what the approved success criteria ask for.

## Risks / Trade-offs

- **Rule is accepted but silently falls back to software** → SC3 measures `flow query` counter hits against testpmd forwarding stats; nonzero forwarded packets means not offloaded, and the verdict is recorded accordingly rather than as a pass.
- **An `rte_flow` NO is an mlx5 PMD exposure gap rather than a silicon limit** → this is the risk that would cause the most expensive wrong decision, since it would retire a viable platform. Mitigated by D6: a NO never stands unqualified, it triggers the DOCA Flow cross-check. A YES is still recorded as *indicative pending DOCA Flow confirmation*, which remains a follow-up.
- **E-switch split-horizon rejects same-port return** → does not fail the spike; routes to D4's PARTIAL branch with the SF topology (Alternative C) as the recorded consequence.
- **DPDK version predates `RTE_FLOW_FIELD_TCP_SEQ_NUM`** → version is read from `/opt/mellanox/dpdk` before rule construction, so an unsupported build is diagnosed as a tooling limit rather than misreported as a hardware NO.
- **Taking `pf0hpf` disrupts other lab users** → the data path is currently idle (`p0` no carrier, `ens16f0np0` down), management runs over the independent `oob_net0`, and the baseline diff in SC5 proves restoration. The runs4 DPU is untouched.
- **The DPU has no working DNS resolver** → the primary probe uses only preinstalled tooling (`dpdk-testpmd`, `ovs-vsctl`, `mlxdevm`, `tcpdump`), and the cross-check's toolchain arrives as a saved container image rather than a package pull. Any step that requires `apt`, `pip`, or a registry pull *on the DPU* is a design error; building the image on a machine that does have DNS and transporting it is the supported path.
- **The cross-check adds container tooling to the spike's surface** → scoped down hard: it answers one question with no hairpin, no capture, and no traffic generation, and it only runs on a NO. The restore path treats a loaded image as state to clean up, same as hugepages.

## Migration Plan

Not a deployed change — nothing ships. The lab-state sequence is:

1. Capture baseline: `ovs-vsctl show`, `pf0hpf` bridge membership, hugepage count, DPDK and firmware versions.
2. Mutate: allocate hugepages on the ARM, detach `pf0hpf` from `ovsbr1`, bring `ens16f0np0` up on the x86 VM.
3. Test: run the harness, collect the three verification levels, write the verdict.
4. Restore: re-attach `pf0hpf` to `ovsbr1`, free hugepages, return `ens16f0np0` to its prior state.
5. Verify restoration by diffing against step 1.

**Rollback**: steps 2–4 are individually reversible and the DPU survives a reboot back to its persisted OVS configuration, so a botched run is recoverable by re-running restore or rebooting the ARM. Management access does not depend on any mutated interface.

## Open Questions

- **Which DPDK version is under `/opt/mellanox/dpdk`?** Determines whether `modify_field` supports TCP seq/ack fields at all. Read it first; it changes how a negative result must be interpreted.
- **Does the mlx5 PMD expose `represented_port` or only the older `port_id` action on this DOCA build?** Affects the exact rule syntax, not the design.
- **Is `dv_flow_en=2` required on the device argument for hardware steering?** `infra/bluefield/deployment/Dockerfile` passes `-a auxiliary:mlx5_core.sf.2,dv_flow_en=2`, so the flag is in use elsewhere in this repo on this hardware. If it gates the steering mode that `modify_field` needs, omitting it would produce a false NO — try it before recording any negative result.
- **Is `delta` best applied as `op sub` on seq for one direction and `op add` on ack for the other?** The T8 design implies both; the spike only needs one direction to answer the capability question, and the verdict document should state which direction was proven.
