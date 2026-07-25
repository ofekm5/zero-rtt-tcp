## Context

The `bluefield-runs3-dpu` (`10.13.36.16`) is a BlueField-3 in DPU mode (`INTERNAL_CPU_MODEL=EMBEDDED_CPU`), e-switch in `switchdev`, DOCA 3.0.0058 with `libdoca_flow`, DPDK under `/opt/mellanox/dpdk`. Its host is the Proxmox VM `bluefield-dev` (`10.13.37.10`), which owns the ConnectX-7 PF by PCIe passthrough and sees it as `ens16f0np0` (`mlx5_core`).

Three facts from live inspection constrain the design:

1. **`p0` is dark** — no carrier, no link partner, and this card has no `p1`. The only data path into the e-switch is `ens16f0np0` ↔ `pf0hpf`, which are two ends of one link, not two ports.
2. **The ARM has no build toolchain** — `meson` and `ninja` are absent, and DNS is broken (resolver `172.27.6.200` does not answer; raw-IP routing works). Anything requiring a compile on the ARM is blocked until that is fixed.
3. **Management is independent of the data path** — the DPU is reached over `oob_net0`, a separate physical port. Taking `pf0hpf` away from `ovsbr1` cannot sever access to the DPU.

Fact 3 is what makes this spike safe to run; facts 1 and 2 are what shape it into a `testpmd` exercise over a single port rather than a compiled two-port program.

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
| Accepted | `flow create` returns a rule ID | The action is not supported at all — decisive NO |
| Offloaded | `flow query <id> count` hits increment **and** testpmd forwarding stats stay at zero | Rule matched but packets are crossing an ARM core — the design's premise fails |
| Effective | `tcpdump` on `ens16f0np0` shows `seq == sent ± delta` | Rule matched and counted but did not actually rewrite — a silent no-op |

All three must hold for YES. The third is the only one that cannot be faked by a permissive PMD.

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

*Tradeoffs*: Zero code to write and no compile step, which matters because `meson`/`ninja` are missing on the ARM and DNS is down. Uses only what is already installed. Costs: `rte_flow` acceptance does not guarantee DOCA Flow exposes the identical action, so a YES carries a small interpretation gap; and same-port return may hit e-switch split-horizon rules, which is why D4 defines the PARTIAL branch.

*Verdict*: **Recommended** — it is the only approach that produces an answer without first unblocking the ARM toolchain, and a NO from it is decisive regardless of the API gap.

### B. Small DOCA Flow C program

Write a minimal DOCA Flow application that builds a pipe with a TCP seq/ack modify action, matching exactly the API the final architecture would use.

*Tradeoffs*: Removes the API interpretation gap entirely — the result transfers with no caveat. But it requires installing `meson` and `ninja` on the ARM first, which requires fixing DNS, which is a separate piece of deployment work. It converts a same-day answer into a multi-step dependency chain, and does so *before* anyone knows whether the capability exists at all.

*Verdict*: **Rejected for this change, retained as a follow-up.** Correct sequencing is cheap-and-indicative first, expensive-and-exact only if the cheap test says YES.

### C. Two-port test using a Scalable Function as egress

Create an SF via `mlxdevm`, then test a transfer rule that matches on `pf0hpf` ingress, rewrites seq/ack, and forwards to the SF representor — capturing on the SF netdev on the ARM.

*Tradeoffs*: Sidesteps the same-port return question completely, so it isolates the rewrite capability cleanly, and its two-port shape is closer to today's `src/servernic/dpdk/` structure. But it changes what is being proven: it verifies rewrite plus vport-to-vport steering, not the return-to-host path the single-port architecture actually needs. It also adds SF lifecycle (create, configure, delete) to the spike's mutation surface and therefore to its restore burden.

*Verdict*: **On the shelf** — explicitly the fallback path when the spike lands on D4's first PARTIAL branch. Not the primary test, because proving the harder composed case first is what the approved success criteria ask for.

## Risks / Trade-offs

- **Rule is accepted but silently falls back to software** → SC3 measures `flow query` counter hits against testpmd forwarding stats; nonzero forwarded packets means not offloaded, and the verdict is recorded accordingly rather than as a pass.
- **`rte_flow` result does not transfer to DOCA Flow** → accepted and documented. A NO is decisive either way; a YES is recorded as *indicative pending DOCA Flow confirmation*, and that confirmation is the named follow-up.
- **E-switch split-horizon rejects same-port return** → does not fail the spike; routes to D4's PARTIAL branch with the SF topology (Alternative C) as the recorded consequence.
- **DPDK version predates `RTE_FLOW_FIELD_TCP_SEQ_NUM`** → version is read from `/opt/mellanox/dpdk` before rule construction, so an unsupported build is diagnosed as a tooling limit rather than misreported as a hardware NO.
- **Taking `pf0hpf` disrupts other lab users** → the data path is currently idle (`p0` no carrier, `ens16f0np0` down), management runs over the independent `oob_net0`, and the baseline diff in SC5 proves restoration. The runs4 DPU is untouched.
- **No package installation is possible on the ARM** → the harness is constrained to preinstalled tooling only (`dpdk-testpmd`, `ovs-vsctl`, `mlxdevm`, `tcpdump`). Any step requiring `apt` is a design error, not a runtime problem to solve.

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
- **Is `delta` best applied as `op sub` on seq for one direction and `op add` on ack for the other?** The T8 design implies both; the spike only needs one direction to answer the capability question, and the verdict document should state which direction was proven.
