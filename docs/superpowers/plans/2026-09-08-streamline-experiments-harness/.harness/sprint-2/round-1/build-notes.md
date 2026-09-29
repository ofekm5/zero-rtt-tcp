# Build notes — sprint 2 round 1

## Changes made
- experiments/run.sh:(new, git mode 100755) — the single entrypoint. Steps in order:
  - Validates `STACK` (0rtt|baseline, default 0rtt) and `TRANSPORT` (ssm|ssh, default ssm) before sourcing anything. An unrecognised value exits 2 with `ERROR: unrecognised STACK='…' — accepted values: 0rtt, baseline` (or `…: ssm, ssh`).
  - Sets `REPO_PATH` in the same `TRANSPORT` case arm that selects the shim: `/home/ec2-user/zero-rtt-tcp` for ssm, `/home/user/zero-rtt-tcp` for ssh.
  - SSM branch: sources `lib/transport/ssm.sh` and adds the `remote_*`→`ssm_*` shims and `REMOTE_OUTPUT_CAP=24000` (the same lines as in dpdk/baseline-tcp `run_experiment.sh`). Adds a stack-aware `discover_nodes` that reads the `smartnics-*` tags for 0rtt and the `baseline-*` tags for baseline. Adds `prologue_0rtt`, which resolves the five MACs from the EC2 API and smoke-tests the ClientNIC forwarder. Its queries, their order, the smoke command and the pass/fail branches are copied from `dpdk/run_experiment.sh:103-180`. The smoke test goes through `remote_run`/`remote_stdout` rather than `ssm_run`/`ssm_stdout`; under SSM these are the same calls.
  - SSH branch: sources `lib/transport/ssh_lab.sh`, which already provides `remote_*` and `discover_nodes`. Its `prologue_0rtt` reads the MACs with `get_lab_mac` and exits 1 on any missing MAC, as `proxmox/run_experiment.sh:68-95` does.
  - Then sources measure.sh, output.sh and core.sh. It discovers nodes, runs `prologue_0rtt` only for `STACK=0rtt`, then runs `run_experiment` with the five MACs (empty strings for baseline). It prints the summary banner and exits with `$FAILURES`.

## Verification commands run
- C1: `( aws() { return 97; }; ssh() { return 97; }; export -f aws ssh; ! o1=$(STACK=quic bash experiments/run.sh 2>&1) && grep -q 0rtt <<< "$o1" && grep -q baseline <<< "$o1" && ! o2=$(TRANSPORT=pigeon bash experiments/run.sh 2>&1) && grep -q ssm <<< "$o2" && grep -q ssh <<< "$o2" )` — exit 0.
  - Raw output was `ERROR: unrecognised STACK='quic' — accepted values: 0rtt, baseline` (rc=2) and `ERROR: unrecognised TRANSPORT='pigeon' — accepted values: ssm, ssh` (rc=2).
- C2: `test -x experiments/run.sh` — exit 0. The git index mode is 100755 (`git ls-files -s`).
- Extra, not a criterion: no remote call on bad input. `aws`/`ssh` were exported as functions that append to a trace file. Running STACK=quic, TRANSPORT=pigeon, and STACK=quic TRANSPORT=ssh recorded 0 calls.
- Extra, not a criterion: offline dispatch smoke. `aws`/`ssh`/`sleep` were exported as stubs returning canned values, and each run was checked against its trace:
  - 0rtt+ssm: exit 9. Reads `smartnics-*` tags only, runs the ClientNIC smoke test, both `meson setup` builds are present, and `REPO_PATH` is /home/ec2-user.
  - baseline+ssm: exit 6. Reads `baseline-*` tags only, with no smoke test and no `meson setup`.
  - 0rtt+ssh: exit 10. `REPO_PATH` is /home/user, MACs are read off the VMs, and both NIC builds are present (as `meson\ setup` because of `printf %q`).
  - These exit codes are the failure counts, which are non-zero because the stubs return canned output.
- `python -m pytest experiments/tests -q` — 74 passed. This includes test_path_refs.py, which checks that run.sh parses and that every path it sources resolves.

## Open concerns
- The global constraint says "`REPO_PATH` … must be derived from the transport shim". run.sh sets it in the `TRANSPORT` case arm that picks the shim; the shim files themselves are unchanged. Also, the SSM `remote_*` shims and the SSM `discover_nodes`/`ec2_mac` live in run.sh, not in `lib/transport/ssm.sh`. The plan allows transport helpers to go under `lib/transport/`, but the contract's criteria name only `run.sh`, so I stayed there. Moving them into `ssm.sh` would affect the dpdk/baseline runners that also source it.
- Testability for sprint 3: run.sh defines `remote_*` itself under SSM, and `ssh_lab.sh` defines them under SSH. So stubbing `remote_run`/`remote_bg`/`remote_stdout` from outside will not override them. A test has to stub one level lower (`aws`/`ssh` as exported functions, as the smoke above did) or run run.sh against a copied tree with stub transport files. Sprint 3 touches only `test_run_sh.py`, so it will need one of these two approaches.
- run.sh writes no report. That is Task 8 / sprint 4 and out of scope here.
- `STACK=baseline TRANSPORT=ssh` is accepted and uses the lab's single set of VMs through `ssh_lab.sh`'s `discover_nodes`. No existing runner covers that combination, and the plan does not pin it.
- The plan doc's `- [ ] 5.2` row is left unmarked, as the 5.1 row was after sprint 1.
- A Bash heredoc write of this file was denied by the sandbox. I wrote it with the Write tool instead.
