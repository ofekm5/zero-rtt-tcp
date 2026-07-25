## Tasks

Harness lives under a new `experiments/bluefield/probe/` directory. It runs from the developer's machine over the RUNS lab OpenVPN tunnel, driving `10.13.36.16` (DPU ARM) and `10.13.37.10` (x86 host VM) over SSH with the existing `claude_code_ed25519` key.

Verify hints for authoring tasks check the artifact itself (syntax, required content). Tasks whose outcome can only be observed against live lab hardware are marked `manual review` — the sandboxed verifier has no VPN, no SSH key, and no DPU.

- [ ] 1. Add SSH transport helper for the two probe hosts — verify: `bash -n experiments/bluefield/probe/lib/hosts.sh`
    - File: `experiments/bluefield/probe/lib/hosts.sh`
    - Outcome: sourcing the file exposes `dpu_run` and `vm_run` helpers that execute a command on `10.13.36.16` and `10.13.37.10` respectively using `~/.ssh/claude_code_ed25519` with `IdentitiesOnly=yes` and `BatchMode=yes`, and return the remote exit status. Host addresses and usernames (`ubuntu` on the DPU, `bluefieldadmin` on the VM) are overridable by environment variable.
    - Commit: `feat(bluefield-probe): add SSH transport helpers for DPU and host VM`

- [ ] 2. Capture the pre-mutation DPU baseline — verify: `bash -n experiments/bluefield/probe/baseline.sh && grep -q 'ovs-vsctl show' experiments/bluefield/probe/baseline.sh`
    - File: `experiments/bluefield/probe/baseline.sh`
    - Outcome: writes `ovs-vsctl show` output, `pf0hpf` bridge membership, ARM hugepage count, the DPDK version found under `/opt/mellanox/dpdk`, and the adapter firmware version to a baseline file, and exits non-zero without mutating the DPU if any value cannot be read. Satisfies the baseline-capture requirement in `specs/eswitch-offload-probe/spec.md`.
    - Commit: `feat(bluefield-probe): capture pre-mutation DPU baseline`

- [ ] 3. Bring up hugepages and bind `pf0hpf` under testpmd — verify: `bash -n experiments/bluefield/probe/setup.sh && grep -q 'dpdk-testpmd' experiments/bluefield/probe/setup.sh`
    - File: `experiments/bluefield/probe/setup.sh`
    - Outcome: allocates hugepages on the ARM, detaches `pf0hpf` from `ovsbr1`, brings `ens16f0np0` up on the x86 VM, and launches `dpdk-testpmd` so it reaches the `testpmd>` prompt with `pf0hpf` listed in `show port summary all`. Uses only preinstalled tooling — no `apt`, `pip`, or other network-dependent installer, per the spec's no-package-installation scenario. Never touches `oob_net0`.
    - Commit: `feat(bluefield-probe): allocate hugepages and bind pf0hpf under testpmd`

- [ ] 4. Construct and install the composed transfer-domain rule — verify: `bash -n experiments/bluefield/probe/flow_rule.sh && grep -q 'tcp_seq_num' experiments/bluefield/probe/flow_rule.sh`
    - File: `experiments/bluefield/probe/flow_rule.sh`
    - Outcome: issues a single `flow create` in the `transfer` domain composing a 5-tuple pattern, a `modify_field` action on `tcp_seq_num` with an ADD or SUB operation and a configurable delta, an egress action toward the host port, and a `count` action; captures the rule ID on success and the verbatim PMD error text on rejection. Reads the recorded DPDK version first and reports a tooling limitation rather than a hardware NO when the build predates `RTE_FLOW_FIELD_TCP_SEQ_NUM`. Rule shape is given in `design.md` decision D1.
    - Commit: `feat(bluefield-probe): install composed transfer-domain seq-rewrite rule`

- [ ] 5. Generate traffic and capture the return leg from the x86 VM — verify: `bash -n experiments/bluefield/probe/traffic.sh && grep -q 'ens16f0np0' experiments/bluefield/probe/traffic.sh`
    - File: `experiments/bluefield/probe/traffic.sh`
    - Outcome: sends TCP packets with a known sequence number out `ens16f0np0` on the x86 VM while capturing on the same interface, and reports the sequence numbers of any returned packets alongside the sequence number sent. Distinguishes three observable outcomes — returned and rewritten, returned unmodified, and nothing returned within the capture window — because `design.md` decision D4 maps them to different verdicts.
    - Commit: `feat(bluefield-probe): generate and capture traffic from the host VM`

- [ ] 6. Evaluate the three verification levels and emit a verdict — verify: `bash -n experiments/bluefield/probe/verdict.sh && grep -q 'PARTIAL' experiments/bluefield/probe/verdict.sh`
    - File: `experiments/bluefield/probe/verdict.sh`
    - Outcome: reads rule acceptance, `flow query <id> count` hits against testpmd's forwarding statistics, and the on-wire capture result, then emits YES, NO, or PARTIAL per the decision table in `design.md` D2 and the branches in D4. A YES requires all three levels to hold and is annotated as indicative pending DOCA Flow confirmation; a PARTIAL names which sub-capability failed and records the Scalable Function egress topology as the applicable fallback; a NO records that no topology change rescues the architecture.
    - Commit: `feat(bluefield-probe): evaluate verification levels and emit verdict`

- [ ] 7. Restore the DPU and verify against the baseline — verify: `bash -n experiments/bluefield/probe/restore.sh && grep -q 'ovsbr1' experiments/bluefield/probe/restore.sh`
    - File: `experiments/bluefield/probe/restore.sh`
    - Outcome: re-attaches `pf0hpf` to `ovsbr1`, frees the hugepages, returns `ens16f0np0` to its recorded state, diffs the resulting `ovs-vsctl show` against the baseline file, and exits non-zero when they differ so an incomplete restoration cannot be reported as success. Runs for every verdict, including failure paths.
    - Commit: `feat(bluefield-probe): restore DPU state and verify against baseline`

- [ ] 8. Add the orchestrator that runs the probe end to end — verify: `bash -n experiments/bluefield/probe/run_probe.sh && grep -q 'restore.sh' experiments/bluefield/probe/run_probe.sh`
    - File: `experiments/bluefield/probe/run_probe.sh`
    - Outcome: runs baseline, setup, flow rule, traffic, and verdict in sequence, and invokes `restore.sh` on every exit path including early failure, so the DPU is never left mutated by an aborted run. Writes the verdict and collected evidence under `experiments/bluefield/reports/`.
    - Commit: `feat(bluefield-probe): add end-to-end probe orchestrator`

- [ ] 9. Document the probe and its prerequisites — verify: `test -s experiments/bluefield/probe/README.md && grep -q 'oob_net0' experiments/bluefield/probe/README.md`
    - File: `experiments/bluefield/probe/README.md`
    - Outcome: states the two target hosts, the VPN and SSH-key prerequisites, what the probe mutates and how it restores, why management over `oob_net0` is unaffected, and how to read a YES, NO, or PARTIAL verdict.
    - Commit: `docs(bluefield-probe): document probe prerequisites and verdict reading`

- [ ] 10. Execute the probe against the runs3 DPU and record the verdict — manual review
    - File: `experiments/bluefield/reports/` (verdict document produced by the run)
    - Outcome: a committed verdict document recording YES, NO, or PARTIAL with the captured `flow create` result, counter and forwarding statistics, the `tcpdump` evidence, and the DPDK and firmware versions the result was obtained on; `ovs-vsctl show` on the DPU matches the pre-spike baseline afterwards. This task requires the RUNS lab tunnel and live hardware, so it cannot be checked by the sandboxed verifier.
    - Commit: `docs(bluefield-probe): record e-switch TCP seq offload verdict`
