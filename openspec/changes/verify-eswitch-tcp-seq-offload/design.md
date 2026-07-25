## Context

The `bluefield-runs3-dpu` (`10.13.36.16`) is a BlueField-3 in DPU mode (`INTERNAL_CPU_MODEL=EMBEDDED_CPU`), e-switch in `switchdev`, DOCA 3.0.0058 with `libdoca_flow`, DPDK under `/opt/mellanox/dpdk`. Its host is the Proxmox VM `bluefield-dev` (`10.13.37.10`), which owns the ConnectX-7 PF by PCIe passthrough and sees it as `ens16f0np0` (`mlx5_core`).

Three facts from live inspection constrain the design:

1. **`p0` is dark** — no carrier, no link partner, and this card has no `p1`. The only data path into the e-switch is `ens16f0np0` ↔ `pf0hpf`, which are two ends of one link, not two ports.
2. **The ARM host OS has no `meson`/`ninja`, and DNS is broken** (resolver `172.27.6.200` does not answer; raw-IP routing works). This is *not* a blocker for compiling: the DOCA devel container ships both tools, and the repo already scripts offline transport — `infra/bluefield/deployment/Dockerfile` builds `FROM nvcr.io/nvidia/doca/doca:2.9.3-devel` and runs `meson`/`ninja` inside it, while `compress_doca_image.sh` and `wire-example/build_wire_image.sh --save` produce a saved image tarball for `scp` + `docker load`. Compiling on the DPU costs a transport step, not a DNS fix.
3. **Management is independent of the data path** — the DPU is reached over `oob_net0`, a separate physical port. Taking `pf0hpf` away from `ovsbr1` cannot sever access to the DPU.

Fact 3 is what makes this spike safe to run; fact 1 is what shapes it into a single-port exercise. Fact 2 costs a transport step and nothing more, which is why the probe is free to use whichever API best answers the question rather than whichever needs no compiler.

That is a correction to an earlier reading of this environment. `command -v meson` returning nothing on the ARM host OS was mistaken for "cannot compile here", and a probe design was built around that constraint; the container path was already present in the repo.

## Goals / Non-Goals

**Goals:**

- Produce a defensible YES / NO / PARTIAL verdict on whether the e-switch can match a TCP flow, rewrite seq/ack by a per-flow constant, and return the packet — all in hardware.
- Distinguish *rule accepted* from *rule offloaded* from *packet actually rewritten*. These are three different things and only the third is decisive.
- Make PARTIAL a meaningful outcome that maps to a concrete architectural fallback, not an inconclusive shrug.
- Leave the DPU byte-for-byte as it was found.

**Non-Goals:**

- Any throughput, latency, or rule-install-rate measurement.
- Reproducing `testpmd`'s interactive surface. The probe parameterises its rule via CLI arguments; that is enough to iterate syntax without rebuilding.
- Multiple concurrent flows or flow-table capacity probing.
- Fixing lab DNS, or installing anything on the DPU that would need a registry pull.

## Decisions

### D1 — Test in the e-switch domain, not the NIC domain

The architecture depends on packets being steered and rewritten by the **e-switch**, so the probe must build its pipe in the e-switch domain rather than as a NIC-domain rule. A NIC-domain rule would prove a different, weaker thing: that a packet can be rewritten on its way to a local queue, which says nothing about e-switch steering between vports.

The probe composes all three properties in one pipe entry:

- **match** the 5-tuple — `eth / ipv4 src,dst / tcp src,dst`
- **modify** the TCP sequence number by a per-flow constant (SUB for client→server ack, ADD for server→client seq; one direction suffices to answer the capability question)
- **egress** back toward the host port
- **count**, attached deliberately — it is how SC3 distinguishes a hardware hit from a software fallback

Every one of these is a CLI argument to the probe, so rule syntax is iterated by re-running the loaded container rather than rebuilding and re-transporting it. That is what makes a compiled probe competitive with an interactive shell for this task.

The `rte_flow` cross-check expresses the same shape in `testpmd` syntax:

```
flow create 0 transfer ingress group 0
  pattern eth / ipv4 src is <client> dst is <server>
        / tcp  src is <sport> dst is <dport> / end
  actions modify_field op sub dst_type tcp_seq_num
                       src_type value src_value <delta> width 32
        / represented_port ethdev_port_id 0
        / count / end
```

### D2 — Three-level verification, because rule acceptance is not evidence

A successful rule-creation call means the API *validated* the rule, not that hardware executes it. The spike therefore checks three independent signals, in order:

| Level | Signal | What a failure here means |
|---|---|---|
| Accepted | rule creation returns a valid handle | The action is not exposed by this API — **ambiguous**, triggers the D6 cross-check |
| Offloaded | the rule's hardware counter increments **and** the probe reports zero packets on an ARM software queue | Rule matched but packets are crossing an ARM core — the design's premise fails |
| Effective | `tcpdump` on `ens16f0np0` shows `seq == sent ± delta` | Rule matched and counted but did not actually rewrite — a silent no-op |

All three must hold for YES. The third is the only one that cannot be faked by a permissive PMD.

### D3 — Generate and capture from the x86 VM, not on the ARM

The probe could generate its own traffic on the ARM, but then the sender, the rewriter, and the receiver are all the same process on the same host — which cannot distinguish a hardware return from the process forwarding a packet in software. Sending real TCP packets from `ens16f0np0` on the x86 VM and capturing on the same interface makes the round trip externally observable, and matches the target architecture's traffic direction.

### D4 — PARTIAL is a defined outcome with a defined consequence

Two sub-capabilities can fail independently, and they have different architectural implications:

- **Rewrite works, same-port return rejected** → e-switch split-horizon is blocking the return leg. The architecture survives by using a Scalable Function as the egress port instead of returning out `pf0hpf`. `mlxdevm` is present at `/opt/mellanox/iproute2/sbin/mlxdevm` and the e-switch is in `switchdev`, so SFs are creatable ARM-side without host or Proxmox involvement.
- **Rewrite rejected** → not yet a NO. Per D6 this first routes to the `rte_flow` cross-check; only if that also rejects the rewrite is a NO recorded, and then no topology change rescues it.

The verdict document must state which of these occurred, because the two lead to different next changes.

### D5 — Restore is a success criterion, not a cleanup step

The DPU is shared lab infrastructure. The baseline (`ovs-vsctl show`, hugepage count, `pf0hpf` bridge membership) is captured **before** any mutation and diffed after, and that diff is SC5. Treating restoration as an acceptance criterion rather than a trailing `cleanup()` is what prevents a half-restored DPU from being reported as a pass.

### D6 — Probe with DOCA Flow first; a NO gets an `rte_flow` cross-check

DOCA Flow and `rte_flow` both compile down to the same mlx5 hardware steering, but they do not expose identical action sets. Two consequences follow.

**Which API probes first.** With the toolchain objection removed, DOCA Flow takes the first pass: it is NVIDIA's recommended path for BF-3, `infra/bluefield/examples/syn-punt/src/doca_flow_handler.c` is in-repo precedent on this exact hardware, and its pipe abstraction matches the architecture's fast-path-plus-punt shape. A positive result therefore proves the API most likely to ship, with no interpretation gap to carry forward.

**Why a negative still needs a second opinion.** The two outcomes are asymmetric:

| Result | Interpretation | Consequence |
|---|---|---|
| **YES** | The silicon performs the rewrite, through the API most likely to ship. | Decisive. No second stage runs. |
| **NO** | Either the silicon cannot do it, **or** DOCA Flow on this build does not expose that action. | **Not decisive.** Run the cross-check. |

Abandoning the platform on an unqualified NO would risk discarding a working architecture over an API gap. So a NO — and only a NO — triggers the same attempt through `rte_flow` driven by the preinstalled `dpdk-testpmd`, which needs no build or transport and so costs almost nothing to run.

The cross-check is deliberately scoped to the single question "does *any* API on this card expose a per-flow TCP seq/ack modify?" It is not a second full probe: no hairpin, no on-wire capture, no traffic generation. Its only job is to disambiguate the NO.

A YES from the cross-check after a NO from DOCA Flow is recorded as PARTIAL, not YES — the capability exists but is reachable only through `rte_flow` on this build, which is exactly the finding that settles the companion change's open API decision.

## Alternatives Considered

### A. Minimal DOCA Flow probe program, e-switch domain, single port — **recommended**

A small DOCA Flow application that builds a pipe with a TCP seq modify action and an egress back out `pf0hpf`, built inside the DOCA devel container, transported as a saved image, and driven by CLI arguments so rule parameters vary without rebuilding.

*Tradeoffs*: Probes the API most likely to ship, so a YES proves the production path with no interpretation gap to carry into the companion change, and it matches in-repo precedent (`syn-punt/src/doca_flow_handler.c`). Costs a one-time container build, save, `scp` and `docker load` before any answer exists — and a rejection still does not prove the silicon lacks the capability, which is what D6's cross-check exists for.

*Verdict*: **Recommended as the primary probe**, paired with the D6 cross-check so its ambiguous negative does not become a wrong platform decision.

### B. `testpmd` / `rte_flow` as the sole probe

Drive the composed rule interactively through the preinstalled `dpdk-testpmd`, using only that.

*Tradeoffs*: Available immediately with zero setup — a first signal in minutes rather than after a container round trip. But it probes an API the companion change may not ship, so a YES carries an interpretation gap. It was also originally preferred on a reason that turned out to be false: that DOCA Flow required an ARM toolchain which could not be installed. The DOCA devel container ships `meson`/`ninja` and the repo already scripts offline transport, so that objection does not hold. Its remaining edge — interactive iteration — is largely neutralised by parameterising the compiled probe.

*Verdict*: **Rejected as the sole probe, adopted as the conditional negative-path stage.** Its zero-setup availability is exactly what makes it a cheap second opinion on a NO.

### C. Two-port test using a Scalable Function as egress

Create an SF via `mlxdevm`, then test a transfer rule that matches on `pf0hpf` ingress, rewrites seq/ack, and forwards to the SF representor — capturing on the SF netdev on the ARM.

*Tradeoffs*: Sidesteps the same-port return question completely, so it isolates the rewrite capability cleanly, and its two-port shape is closer to today's `src/servernic/dpdk/` structure. But it changes what is being proven: it verifies rewrite plus vport-to-vport steering, not the return-to-host path the single-port architecture actually needs. It also adds SF lifecycle (create, configure, delete) to the spike's mutation surface and therefore to its restore burden.

*Verdict*: **On the shelf** — explicitly the fallback path when the spike lands on D4's first PARTIAL branch. Not the primary test, because proving the harder composed case first is what the approved success criteria ask for.

## Risks / Trade-offs

- **Rule is accepted but silently falls back to software** → SC3 measures the rule's hardware counter against the probe's software-queue receive count; nonzero software receipts means not offloaded, and the verdict is recorded accordingly rather than as a pass.
- **A DOCA Flow NO is an API exposure gap rather than a silicon limit** → the risk that would cause the most expensive wrong decision, since it would retire a viable platform. Mitigated by D6: a NO never stands unqualified, it triggers the `rte_flow` cross-check, which needs no build or transport.
- **E-switch split-horizon rejects same-port return** → does not fail the spike; routes to D4's PARTIAL branch with the SF topology (Alternative C) as the recorded consequence.
- **The installed DOCA or DPDK build predates TCP seq/ack modify support** → both versions are read before rule construction, so an unsupported build is diagnosed as a tooling limit rather than misreported as a hardware NO.
- **Taking `pf0hpf` disrupts other lab users** → the data path is currently idle (`p0` no carrier, `ens16f0np0` down), management runs over the independent `oob_net0`, and the baseline diff in SC5 proves restoration. The runs4 DPU is untouched.
- **The DPU has no working DNS resolver** → the probe's toolchain arrives as a saved container image built elsewhere, and the cross-check uses only preinstalled tooling (`dpdk-testpmd`, `ovs-vsctl`, `mlxdevm`, `tcpdump`). Any step requiring `apt`, `pip`, or a registry pull *on the DPU* is a design error.
- **The container adds state to the spike's mutation surface** → the restore path treats a loaded image as state to clean up, same as hugepages, and the baseline diff in SC5 covers it. The cross-check itself adds nothing: no build, no transport, and it runs only on a NO.

## Migration Plan

Not a deployed change — nothing ships. The lab-state sequence is:

1. Capture baseline: `ovs-vsctl show`, `pf0hpf` bridge membership, hugepage count, DPDK and firmware versions.
2. Mutate: allocate hugepages on the ARM, detach `pf0hpf` from `ovsbr1`, `docker load` the probe image, bring `ens16f0np0` up on the x86 VM.
3. Test: run the harness, collect the three verification levels, write the verdict.
4. Restore: re-attach `pf0hpf` to `ovsbr1`, free hugepages, remove the loaded image, return `ens16f0np0` to its prior state.
5. Verify restoration by diffing against step 1.

**Rollback**: steps 2–4 are individually reversible and the DPU survives a reboot back to its persisted OVS configuration, so a botched run is recoverable by re-running restore or rebooting the ARM. Management access does not depend on any mutated interface.

## Open Questions

- **Which DOCA and DPDK versions are installed?** Determines whether TCP seq/ack modification is expressible at all. Read both first; they change how a negative result must be interpreted.
- **Which egress action does DOCA Flow expose for returning to the host port on this build?** Affects the exact pipe construction, not the design. The `rte_flow` equivalent (`represented_port` versus the older `port_id`) matters only for the cross-check.
- **Is `dv_flow_en=2` required on the device argument for hardware steering?** `infra/bluefield/deployment/Dockerfile` passes `-a auxiliary:mlx5_core.sf.2,dv_flow_en=2`, so the flag is in use elsewhere in this repo on this hardware. If it gates the steering mode that `modify_field` needs, omitting it would produce a false NO — try it before recording any negative result.
- **Is `delta` best applied as `op sub` on seq for one direction and `op add` on ack for the other?** The T8 design implies both; the spike only needs one direction to answer the capability question, and the verdict document should state which direction was proven.
