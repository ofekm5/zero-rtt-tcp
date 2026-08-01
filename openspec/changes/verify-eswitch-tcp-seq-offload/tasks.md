## Tasks

Harness lives under a new `experiments/bluefield/probe/` directory. It runs from the developer's machine over the RUNS lab OpenVPN tunnel, driving `10.13.36.16` (DPU ARM) and `10.13.37.10` (x86 host VM) over SSH with the existing `claude_code_ed25519` key.

The primary probe is a DOCA Flow program built in the DOCA devel container and transported as a saved image; the `rte_flow` cross-check uses the preinstalled `dpdk-testpmd` and runs only on a NO, per `design.md` D6.

Verify hints for authoring tasks check the artifact itself (syntax, required content). Tasks whose outcome can only be observed against live lab hardware are marked `manual review` — the sandboxed verifier has no VPN, no SSH key, no DPU, and no Docker daemon.

- [x] 1. Add SSH transport helper for the two probe hosts — verify: `bash -n experiments/bluefield/probe/lib/hosts.sh`
    - File: `experiments/bluefield/probe/lib/hosts.sh`
    - Outcome: sourcing the file exposes `dpu_run` and `vm_run` helpers that execute a command on `10.13.36.16` and `10.13.37.10` respectively using `~/.ssh/claude_code_ed25519` with `IdentitiesOnly=yes` and `BatchMode=yes`, and return the remote exit status. Host addresses and usernames (`ubuntu` on the DPU, `bluefieldadmin` on the VM) are overridable by environment variable.
    - Commit: `feat(bluefield-probe): add SSH transport helpers for DPU and host VM`

- [x] 2. Capture the pre-mutation DPU baseline — verify: `bash -n experiments/bluefield/probe/baseline.sh && grep -q 'ovs-vsctl show' experiments/bluefield/probe/baseline.sh`
    - File: `experiments/bluefield/probe/baseline.sh`
    - Outcome: writes `ovs-vsctl show` output, `pf0hpf` bridge membership, ARM hugepage count, the DOCA and DPDK versions found on the DPU, and the adapter firmware version to a baseline file, and exits non-zero without mutating the DPU if any value cannot be read. Satisfies the baseline-capture requirement in `specs/eswitch-offload-probe/spec.md`.
    - Commit: `feat(bluefield-probe): capture pre-mutation DPU baseline`

- [x] 3. Write the DOCA Flow probe program — verify: `grep -q 'doca_flow' experiments/bluefield/probe/docaprobe/probe.c && grep -q 'argv' experiments/bluefield/probe/docaprobe/probe.c`
    - File: `experiments/bluefield/probe/docaprobe/probe.c`, `experiments/bluefield/probe/docaprobe/meson.build`
    - Outcome: builds a DOCA Flow pipe in the e-switch domain composing a 5-tuple match, a TCP sequence-number modification by a per-flow constant, an egress back toward the host port, and a counter — the shape given in `design.md` D1. The 5-tuple, delta and egress target are command-line arguments so rule syntax is iterated by re-running rather than rebuilding. Reports the created handle, the counter value, and its own software-queue receive count, since those are what SC2 and SC3 measure.
    - Commit: `feat(bluefield-probe): add DOCA Flow seq-rewrite probe program`

- [x] 4. Build and transport the probe image to the DPU — verify: `bash -n experiments/bluefield/probe/build_image.sh && grep -q 'docker save' experiments/bluefield/probe/build_image.sh`
    - File: `experiments/bluefield/probe/build_image.sh`, `experiments/bluefield/probe/docaprobe/Dockerfile`
    - Outcome: builds the probe inside the DOCA devel container — which ships `meson` and `ninja` — on a host with working DNS, saves it to a tarball, transfers it to the DPU and loads it there. Follows the existing `infra/bluefield/deployment/Dockerfile` and `compress_doca_image.sh` pattern. Performs no registry pull or DNS resolution from the DPU, per the transported-toolchain scenario in the spec.
    - Commit: `feat(bluefield-probe): build and transport probe image to the DPU`

- [x] 5. Allocate hugepages and initialise the data-plane port — verify: `bash -n experiments/bluefield/probe/setup.sh && grep -q 'pf0hpf' experiments/bluefield/probe/setup.sh`
    - File: `experiments/bluefield/probe/setup.sh`
    - Outcome: allocates hugepages on the ARM, detaches `pf0hpf` from `ovsbr1`, brings `ens16f0np0` up on the x86 VM, and starts the probe so its output reports `pf0hpf` initialised without error. Never touches `oob_net0`, over which DPU management runs.
    - Commit: `feat(bluefield-probe): allocate hugepages and initialise pf0hpf`

- [x] 6. Install the composed e-switch rule and capture the result — verify: `bash -n experiments/bluefield/probe/flow_rule.sh && grep -q 'delta' experiments/bluefield/probe/flow_rule.sh`
    - File: `experiments/bluefield/probe/flow_rule.sh`
    - Outcome: invokes the probe with the 5-tuple, delta and egress target, capturing either the returned handle or the verbatim error text. Reads the recorded DOCA and DPDK versions first and reports a tooling limitation rather than a hardware NO when the build predates TCP sequence-number modification. Attempts `dv_flow_en=2` on the device argument before recording any negative, since `infra/bluefield/deployment/Dockerfile` uses that flag on this hardware and omitting it could produce a false NO.
    - Commit: `feat(bluefield-probe): install composed e-switch seq-rewrite rule`

- [x] 7. Generate traffic and capture the return leg from the x86 VM — verify: `bash -n experiments/bluefield/probe/traffic.sh && grep -q 'ens16f0np0' experiments/bluefield/probe/traffic.sh`
    - File: `experiments/bluefield/probe/traffic.sh`
    - Outcome: sends TCP packets with a known sequence number out `ens16f0np0` on the x86 VM while capturing on the same interface, and reports the sequence numbers of any returned packets alongside the sequence number sent. Distinguishes three observable outcomes — returned and rewritten, returned unmodified, and nothing returned within the capture window — because `design.md` D4 maps them to different verdicts.
    - Commit: `feat(bluefield-probe): generate and capture traffic from the host VM`

- [x] 8. Add the conditional `rte_flow` cross-check — verify: `bash -n experiments/bluefield/probe/crosscheck.sh && grep -q 'dpdk-testpmd' experiments/bluefield/probe/crosscheck.sh`
    - File: `experiments/bluefield/probe/crosscheck.sh`
    - Outcome: runs only when the DOCA Flow probe returned a negative result, and attempts the same TCP sequence-number modification through `rte_flow` using the preinstalled `dpdk-testpmd`, to distinguish a silicon limit from a DOCA Flow exposure gap per `design.md` D6. Requires no build, image transport, or package installation. Scope is disambiguation only: no hairpin, no traffic generation, no capture.
    - Commit: `feat(bluefield-probe): add conditional rte_flow cross-check for negative results`

- [x] 9. Evaluate the verification levels and emit a verdict — verify: `bash -n experiments/bluefield/probe/verdict.sh && grep -q 'PARTIAL' experiments/bluefield/probe/verdict.sh`
    - File: `experiments/bluefield/probe/verdict.sh`
    - Outcome: reads rule acceptance, the hardware counter against the probe's software-queue receive count, the on-wire capture result, and the cross-check result when one was run, then emits YES, NO, or PARTIAL per the decision tables in `design.md` D2, D4 and D6. A YES requires all three levels to hold. A NO is emitted only after a negative cross-check. A cross-check that succeeds where DOCA Flow failed yields PARTIAL, recording that the capability exists but is reachable only through `rte_flow` on this build.
    - Commit: `feat(bluefield-probe): evaluate verification levels and emit verdict`

- [x] 10. Restore the DPU and verify against the baseline — verify: `bash -n experiments/bluefield/probe/restore.sh && grep -q 'ovsbr1' experiments/bluefield/probe/restore.sh`
    - File: `experiments/bluefield/probe/restore.sh`
    - Outcome: re-attaches `pf0hpf` to `ovsbr1`, frees the hugepages, removes the loaded probe image, returns `ens16f0np0` to its recorded state, diffs the resulting `ovs-vsctl show` against the baseline file, and exits non-zero when they differ so an incomplete restoration cannot be reported as success. Runs for every verdict, including failure paths.
    - Commit: `feat(bluefield-probe): restore DPU state and verify against baseline`

- [ ] 11. Add the orchestrator that runs the probe end to end — verify: `bash -n experiments/bluefield/probe/run_probe.sh && grep -q 'restore.sh' experiments/bluefield/probe/run_probe.sh`
    - File: `experiments/bluefield/probe/run_probe.sh`
    - Outcome: runs baseline, image build and transport, setup, rule installation, traffic, the cross-check when the probe was negative, and verdict in sequence, and invokes `restore.sh` on every exit path including early failure, so the DPU is never left mutated by an aborted run. Writes the verdict and collected evidence under `experiments/bluefield/reports/`.
    - Commit: `feat(bluefield-probe): add end-to-end probe orchestrator`

- [ ] 12. Document the probe and its prerequisites — verify: `test -s experiments/bluefield/probe/README.md && grep -q 'oob_net0' experiments/bluefield/probe/README.md`
    - File: `experiments/bluefield/probe/README.md`
    - Outcome: states the two target hosts, the VPN and SSH-key prerequisites, what the probe mutates and how it restores, why management over `oob_net0` is unaffected, how the container image is built elsewhere and transported rather than pulled, and how to read a YES, NO, or PARTIAL verdict including the cross-check branch.
    - Commit: `docs(bluefield-probe): document probe prerequisites and verdict reading`

- [ ] 13. Execute the probe against the runs3 DPU and record the verdict — manual review
    - File: `experiments/bluefield/reports/` (verdict document produced by the run)
    - Outcome: a committed verdict document recording YES, NO, or PARTIAL with the captured rule-creation result, counter and software-receive statistics, the `tcpdump` evidence, the cross-check result when one was run, and the DOCA, DPDK and firmware versions the result was obtained on; `ovs-vsctl show` on the DPU matches the pre-spike baseline afterwards. This task requires the RUNS lab tunnel and live hardware, so it cannot be checked by the sandboxed verifier.
    - Commit: `docs(bluefield-probe): record e-switch TCP seq offload verdict`
