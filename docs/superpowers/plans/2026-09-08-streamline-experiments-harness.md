# Streamline the experiments harness

**Goal:** Collapse `experiments/` from six entrypoints across four stack folders to a
single `experiments/run.sh` parameterised on `STACK` (`0rtt` | `baseline`) and
`TRANSPORT` (`ssm` | `ssh`), with every shared helper defined exactly once and each
directory meaning one thing.

**Architecture:** `experiments/run.sh` sources one transport shim
(`lib/transport/{ssm,ssh_lab}.sh`) and the shared `lib/core.sh`, then dispatches on
`STACK`. Laptop-side code lives in `lib/`; VM-side code lives in `nodes/`; multi-run
wrappers in `sweeps/`; outputs in `reports/{0rtt,baseline}/`; offline checks in
`tests/`.

**Tech Stack:** Bash (POSIX-ish, `set -uo pipefail`), Python 3 + pytest.

**Spec:** `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`

**Global Constraints:**
- No change to `src/` — the data plane is untouched.
- No change to measurement semantics: `run_core.sh`, `measure.sh`, `endpoint.sh`,
  `analyze_metrics.py` and `loadgen.py` move and are re-sourced, but their logic,
  metric definitions and emitted formats stay byte-identical. **Byte-identity covers
  behaviour, not the whole file:** repointing a path string — a `source` line, or a
  remote command string naming a moved script — is explicitly exempt and is *required*
  wherever a move invalidates it (see Task 3 and Task 4). A "moves byte-identical"
  contract that forbids those edits is wrong and leaves the harness unable to find its
  scripts on the VMs.
- Every `verify:` command runs offline — no AWS, no live VMs, no Docker daemon.
- Historical reports under `experiments/dpdk/reports/` and
  `experiments/baseline-tcp/reports/` are never moved, renamed, or deleted; nothing
  under `docs/openspec/changes/archive/` or `docs/kb/raw/` is edited.
- `STACK=baseline` has no data plane: the shared core must *skip* the NIC build,
  start and log-collection steps for it, not fail them.
- `REPO_PATH` differs per transport (`/home/ec2-user/zero-rtt-tcp` for SSM,
  `/home/user/zero-rtt-tcp` for the lab) and must be derived from the transport shim.

---

- [x] 1 Hoist the duplicated output helpers into a single shared file — verify: `test -f experiments/lib/output.sh && grep -q '^log()' experiments/lib/output.sh && [ "$(grep -l '^log()' experiments/dpdk/run_experiment.sh experiments/baseline-tcp/run_experiment.sh experiments/proxmox/run_experiment.sh experiments/scapy/run_experiment.sh | wc -l)" -eq 0 ]`
    - File: `experiments/lib/output.sh` (new); callers `experiments/dpdk/run_experiment.sh`, `experiments/baseline-tcp/run_experiment.sh`, `experiments/proxmox/run_experiment.sh`, `experiments/scapy/run_experiment.sh`
    - Outcome: `log()`, `pass()`, `fail()`, `warn()` and the `RED`/`GREEN`/`YELLOW`/`NC` colour variables are defined in exactly one place and sourced by every runner. The four byte-identical copies (`dpdk:55-58`, `baseline-tcp:52-55`, `proxmox:51-54`, `scapy:54-57`) are gone. Scope is the four runners only: the VM-executed scripts (`dpdk/{clientnic,servernic}.sh`, `nodes/{client,server}.sh`, `scapy/{clientnic,servernic}.sh`, `run_think_sweep.sh`, `utils/tests/endpoint_mock_harness.sh`) each keep their own `log()` — they run on a remote VM or in a stub harness and cannot source a laptop-side lib. A repo-wide `log()` count is therefore not a valid criterion for this task. `FAILURES` accounting behaves exactly as before. All four runners still execute end to end.
    - Commit: `refactor(experiments): extract shared output helpers to lib/output.sh`

- [x] 2 Merge the two duplicated report writers into one parameterised writer — verify: `[ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ] && bash -n experiments/lib/report.sh`
    - File: `experiments/lib/report.sh` (new); sources replaced in `experiments/dpdk/run_experiment.sh:201-286` and the equivalent block in `experiments/baseline-tcp/run_experiment.sh`
    - Outcome: one function emits the run report for either stack, taking the stack identity and the `CORE_*` result variables as inputs. The DPDK report keeps its implementation stanza, its `LOAD_RATE=0` capacity-run warning, its Load Parameters table and all five body sections; the baseline report keeps its own equivalents. Reports produced for a given stack are textually equivalent to what that stack produced before.
    - Commit: `refactor(experiments): unify the DPDK and baseline report writers`

- [x] 3 Rehome laptop-side code to `lib/` and split the transports out — verify: `test -f experiments/lib/core.sh -a -f experiments/lib/transport/ssm.sh -a -f experiments/lib/transport/ssh_lab.sh -a ! -d experiments/utils`
    - File/area: `experiments/utils/` → `experiments/lib/` (`run_core.sh` → `core.sh`, plus `endpoint.sh`, `measure.sh`); `ssm.sh` and `ssh_lab.sh` → `experiments/lib/transport/`; `experiments/utils/tests/` → `experiments/tests/`
    - Outcome: `experiments/utils/` no longer exists. Every `source` path resolves in all four runners — `experiments/dpdk/run_experiment.sh`, `experiments/baseline-tcp/run_experiment.sh`, `experiments/proxmox/run_experiment.sh`, `experiments/scapy/run_experiment.sh` — and in the moved files. All four are touched by this task: every one of them sources `experiments/utils/*`, so moving that directory breaks all four, not just `experiments/dpdk`. The moved pytest files import their targets at the new paths and still pass. `endpoint_mock_harness.sh` moves with the tests and still works.
    - Commit: `refactor(experiments): move laptop-side code to lib/ with transports split out`

- [x] 4 Rehome every VM-executed script to `nodes/` — verify: `test -f experiments/nodes/client.sh -a -f experiments/nodes/server.sh -a -f experiments/nodes/clientnic.sh -a -f experiments/nodes/servernic.sh -a -f experiments/nodes/loadgen.py -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"`
    - File/area: `experiments/dpdk/{clientnic,servernic}.sh`, `experiments/lib/{loadgen,analyze_metrics}.py` → `experiments/nodes/`
    - Outcome: all six scripts that execute on a remote VM live in `experiments/nodes/` alongside the existing `client.sh` and `server.sh`. Every remote command string that names one of them (in `lib/core.sh`, `lib/endpoint.sh`, `lib/measure.sh`, `nodes/client.sh`, `nodes/server.sh`) uses the new path. `analyze_metrics.py` remains directly invocable on a downloaded pcap, since the `offline-analysis` skill runs it locally.
    - Commit: `refactor(experiments): move all VM-executed scripts into nodes/`

- [ ] 5.1 Make the shared flow in `lib/core.sh` honour `STACK` — verify: `( f=$(mktemp); remote_run() { printf '%s\n' "$2" >> "$f"; echo '["Success","",""]'; }; remote_bg() { printf '%s\n' "$2" >> "$f"; }; remote_stdout() { printf '%s\n' "$2" >> "$f"; }; ssm_run() { remote_run "$@"; }; json_idx() { :; }; sleep() { :; }; log() { :; }; pass() { :; }; fail() { :; }; warn() { :; }; source experiments/lib/measure.sh; source experiments/lib/core.sh; SERVER_PORT=8080 CONNECTIONS=1 REPO_PATH=/r LOAD_PARALLEL=100 FAILURES=0 SERVER_ID=s SERVERNIC_ID=sn CLIENTNIC_ID=cn CLIENT_ID=c SERVER_IP=10.1.2.10; STACK=baseline run_experiment "" "" "" "" "" > /dev/null 2>&1; b=$(cat "$f"); : > "$f"; unset STACK; run_experiment m1 m2 m3 m4 m5 > /dev/null 2>&1; z=$(cat "$f"); rm -f "$f"; ! grep -qE 'meson setup|nodes/(client|server)nic\.sh|/tmp/(client|server)nic\.log' <<< "$b" && grep -qF 'nodes/server.sh' <<< "$b" && grep -qF 'ip route show 10.1.2.0/24' <<< "$b" && grep -qF 'netem delay' <<< "$b" && grep -qF 'meson setup' <<< "$z" && grep -qF 'nodes/servernic.sh' <<< "$z" && grep -qF 'nodes/clientnic.sh' <<< "$z" )`
    - File: `experiments/lib/core.sh`; the baseline steps come from `experiments/baseline-tcp/run_experiment.sh`
    - Outcome: `run_experiment` reads `STACK` and treats an unset value as `0rtt`. `STACK=0rtt` issues the same remote calls as today. `STACK=baseline` runs the plain-TCP flow that `baseline-tcp/run_experiment.sh` runs today: the NIC IP-forwarding and static-route pre-flight, netem on the middle leg (`wan_tune_middle_leg`), server start, load, endpoint captures and the server-log check. It skips the NIC cleanup, both NIC builds, both NIC start steps, the NIC stop and the NIC log collection, and it accepts `""` for the five MACs. The four runners are untouched and still work, because none of them sets `STACK`. The verify shims the transport, runs `run_experiment` once per stack, and asserts on the recorded remote commands.
    - Commit: `refactor(experiments): fold the baseline flow into lib/core.sh behind STACK`

- [ ] 5.2 Add `experiments/run.sh`, the single entrypoint with `STACK`/`TRANSPORT` dispatch — verify: `( aws() { return 97; }; ssh() { return 97; }; export -f aws ssh; ! o1=$(STACK=quic bash experiments/run.sh 2>&1) && grep -q 0rtt <<< "$o1" && grep -q baseline <<< "$o1" && ! o2=$(TRANSPORT=pigeon bash experiments/run.sh 2>&1) && grep -q ssm <<< "$o2" && grep -q ssh <<< "$o2" )`
    - File: `experiments/run.sh` (new, executable). Transport-specific helpers may go in `experiments/lib/transport/`.
    - Outcome: `./experiments/run.sh` runs the 0-RTT stack over SSM by default. `TRANSPORT=ssh` selects the lab shim and its `REPO_PATH`. It discovers the chosen stack's nodes through the transport. For `STACK=0rtt` it also runs that transport's prologue before the shared flow: over SSM it resolves the five MACs from the EC2 API and smoke-tests the ClientNIC forwarder, as `dpdk/run_experiment.sh` does; over SSH it reads the MACs off the VMs, as `proxmox/run_experiment.sh` does. It then calls `run_experiment` from `lib/core.sh`. An unrecognised `STACK` or `TRANSPORT` exits non-zero before any remote call, with a message naming the accepted values (`0rtt`, `baseline`; `ssm`, `ssh`). The exit code is still the failure count. Writing the run report belongs to Task 8, and the four runners stay until Task 7.
    - Commit: `feat(experiments): add single run.sh entrypoint with STACK/TRANSPORT dispatch`

- [ ] 6 Add the mock-transport test that pins the remote-call sequence — verify: `pytest experiments/tests/test_run_sh.py -q`
    - File: `experiments/tests/test_run_sh.py` (new), following the stubbing pattern in `experiments/tests/endpoint_mock_harness.sh` and `experiments/tests/test_endpoint_sh.py`
    - Outcome: the test stubs `remote_run`, `remote_bg` and `remote_stdout` to record their invocations, runs `run.sh` for `0rtt`+`ssm`, `0rtt`+`ssh` and `baseline`+`ssm`, and asserts the ordered call sequence and exit code for each. The expected sequences are recorded from `dpdk/run_experiment.sh`, `proxmox/run_experiment.sh` and `baseline-tcp/run_experiment.sh` while they still exist. Those pinned lists are the parity check, so the test carries no separate test that runs the old runners. The two 0-RTT sequences differ in their transport prologue (SSM smoke-tests the ClientNIC forwarder; the lab reads MACs off the VMs); after the prologue they differ only in `REPO_PATH`. The baseline sequence contains no NIC build or NIC start call. The test fails if a step is dropped, added, or reordered.
    - Commit: `test(experiments): pin run.sh remote-call sequence with a mock transport`

- [ ] 7 Delete the four runners and the Scapy stack; move the sweeps — verify: `test -z "$(find experiments -name run_experiment.sh)" && test ! -d experiments/scapy && test -f experiments/sweeps/think.sh -a -f experiments/sweeps/stress.sh`
    - File/area: delete `experiments/{dpdk,baseline-tcp,proxmox,scapy}/run_experiment.sh` and `experiments/scapy/`; move `experiments/run_think_sweep.sh` → `experiments/sweeps/think.sh` and `experiments/dpdk/run_stress.sh` → `experiments/sweeps/stress.sh`
    - Outcome: `run.sh` is the only orchestrator. `sweeps/think.sh` selects its stack via `STACK` instead of the `case` at `run_think_sweep.sh:40-41`; `sweeps/stress.sh` still sets `LOAD_RATE=0`, still prints its capacity-run caveat, and execs `run.sh`. `experiments/dpdk/probes/` is retained at its current path. Both sweeps run to the point of node discovery without a "no such file" error.
    - Commit: `refactor(experiments): delete the four runners and the deprecated Scapy stack`

- [ ] 8 Write `run.sh`'s report under `reports/{0rtt,baseline}/` — verify: `pytest experiments/tests/test_report_path.py -q && test -d experiments/reports/0rtt -a -d experiments/reports/baseline`
    - File: `experiments/lib/report.sh`, `experiments/run.sh`, `experiments/reports/{0rtt,baseline}/` (new, each with a `.gitkeep`), `experiments/tests/test_report_path.py` (new), `experiments/README.md`
    - Test outcome: the new test invokes the report writer for each stack with stubbed `CORE_*` values in a temp tree and asserts the file lands under `experiments/reports/<stack>/` with that stack's filename convention. It fails if either stack writes outside its directory.
    - Outcome: after `run_experiment`, `run.sh` writes the report for its `STACK`/`TRANSPORT`, with the body the matching runner writes today (`dpdk/`, `proxmox/` or `baseline-tcp/run_experiment.sh`). This task runs before Task 7 deletes those runners. A completed run writes its report under `experiments/reports/<stack>/` with the filename convention that stack already used. `experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/` are left untouched with all their existing files, and a short note in `experiments/README.md` records that they are frozen historical output.
    - Commit: `refactor(experiments): write new reports under reports/<stack>/`

- [ ] 9 Update every caller of the old entrypoints — verify: `! grep -rn 'run_experiment\.sh' .github/workflows/ .claude/skills/ CLAUDE.md experiments/README.md experiments/run.sh experiments/lib/ experiments/nodes/ experiments/sweeps/ --include='*.yml' --include='*.md' --include='*.sh'`
    - File/area: `.github/workflows/run-experiment.yml`, `.claude/skills/run-experiment/SKILL.md`, `.claude/skills/run-experiment/references/test-scripts.md`, `.claude/skills/run-experiment/references/troubleshooting.md`, `.claude/skills/offline-analysis/SKILL.md`, `CLAUDE.md`, `experiments/README.md`
    - Out of scope for this task: `experiments/*/reports/`, `experiments/ci-results/`, `experiments/insights.md` and `experiments/measurement-methodology-review.md` keep their historical references and are not edited.
    - Outcome: the workflow invokes `experiments/run.sh` with `STACK`/`TRANSPORT` derived from its existing `infra` input, and the `EXP_DIR` variable is gone from all nine sites (`:113-115, 210, 213, 215, 255, 275, 298-301, 346, 360, 367`); its report-collection and commit steps target `experiments/reports/`. Both skills describe the one entrypoint and its two variables. `CLAUDE.md`'s module tree matches the new layout, including the removal of the stale `experiments/archive/` entry it still lists. Files under `docs/openspec/changes/archive/` and `docs/kb/raw/` are not edited.
    - Commit: `docs(experiments): retarget workflow, skills and CLAUDE.md at run.sh`

- [ ] 10 Rewrite the roadmap section to match the corrected ordering — manual review
    - File: `roadmap.md`
    - Outcome: the "Human-readable experiment output" section records that harness consolidation landed first and links this change; its "Refine `experiments/` while doing it" subsection is replaced by what remains open (report-artifact pruning). The claim that the run stream is parsed by the skill and `analyze_metrics.py` is corrected — `analyze_metrics.py` parses `tcpdump -r` output on the capture host and the workflow only `tee`s the stream to a file, so no machine contract constrains the format. The status-snapshot table row is updated.
    - Manual because the outcome is prose: the only available check (`grep` for the change name and `run.sh`) proves the words exist, not that the section is correct.
    - Commit: `docs(roadmap): correct the experiment-output section and its ordering`

## Human-Owned Areas

- (none; every touched path is verifiable in the sandbox or has no live effect: `experiments/`, `.github/workflows/run-experiment.yml` (runs only on manual `workflow_dispatch`), `.claude/skills/run-experiment/`, `.claude/skills/offline-analysis/`, `CLAUDE.md`)

## Sprint Graph

Tasks 1–4 are done (1–2 in PR #36, 3–4 in PR #38) and belong to no sprint. Task 10 is `manual review` and stays human work. Task 5 is split so that no sprint's first build round comes near the 400-inserted-line budget. Run 2's single Tasks 5+6 round inserted 1,043 lines. Sprint 4 (Task 8) runs before sprint 5 (Task 7) because it copies each report body out of a runner that Task 7 deletes.

```sprint-graph
{
  "maxParallel": 1,
  "sprints": [
    { "id": 1, "name": "core.sh honours STACK", "tasks": [5.1], "dependsOn": [], "touches": ["experiments/lib/core.sh"] },
    { "id": 2, "name": "run.sh dispatch", "tasks": [5.2], "dependsOn": [1], "touches": ["experiments/run.sh", "experiments/lib/transport"] },
    { "id": 3, "name": "pin run.sh remote-call sequence", "tasks": [6], "dependsOn": [2], "touches": ["experiments/tests/test_run_sh.py"] },
    { "id": 4, "name": "run.sh report under reports/<stack>/", "tasks": [8], "dependsOn": [3], "touches": ["experiments/run.sh", "experiments/lib/report.sh", "experiments/reports", "experiments/tests", "experiments/README.md"] },
    { "id": 5, "name": "delete the runners, move the sweeps", "tasks": [7], "dependsOn": [4], "touches": ["experiments"] },
    { "id": 6, "name": "retarget callers at run.sh", "tasks": [9], "dependsOn": [5], "touches": [".github/workflows/run-experiment.yml", ".claude/skills/run-experiment", ".claude/skills/offline-analysis", "CLAUDE.md", "experiments/README.md", "experiments/run.sh", "experiments/lib", "experiments/nodes", "experiments/sweeps"] }
  ],
  "humanOwned": [],
  "waves": [[1], [2], [3], [4], [5], [6]]
}
```

triage-verdict: ok
