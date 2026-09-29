# Findings — spec-decision lens — sprint 3 round 1

No findings under this lens.

Notes (not findings): checked the round's sole change (`experiments/tests/test_run_sh.py`,
329 lines, no production code touched) against the design doc resolved via
`docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`'s `Spec:` header
(`docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`):

- "Behaviour is preserved... measured by: `pytest experiments/tests/test_run_sh.py -q`"
  is this design's own literal Success Criterion for C1; the test implements exactly the
  chosen "mock-transport pytest" verification approach from `## Alternatives Considered`
  (stubs `remote_run`/`remote_bg`/`remote_stdout` and, on SSM, `ssm_run`/`ssm_bg`/`ssm_stdout`;
  records ordered calls; no AWS/SSH/Docker/live VM touched).
- `STACK=baseline` sequence omits NIC build/start/log-collection steps and is asserted by a
  dedicated test (`test_baseline_issues_no_nic_build_or_start`) — matches the "no data plane"
  constraint.
- `REPO_PATH` is transport-derived (`_SSM_REPO`/`_SSH_REPO` constants match the design's stated
  paths) rather than hardcoded once.
- The docstring confirms "there is deliberately no test that runs the old runners" — matches
  the design's explicit rejection of that approach.
- Considered flagging: `EXPECTED[("0rtt","ssh")]` pins exit code 1 and no client-load call,
  which reads in tension with the Key Constraints bullet "`STACK=0rtt` must work over both
  `ssm` and `ssh`". Traced the cause (`experiments/lib/measure.sh`'s `run_ttfb_measurement`
  calls `ssm_run` directly rather than the transport-neutral `remote_run`, which
  `experiments/lib/transport/ssh_lab.sh` never defines) and confirmed via the test's own
  docstring this is inherited, byte-identical behaviour from `proxmox/run_experiment.sh`
  ("exactly as proxmox/run_experiment.sh... the load step fails with 'command not found'"),
  not something introduced by this round's diff. Sprint 3's contract and out-of-scope list
  forbid touching `lib/core.sh`, `run.sh`, or the transport shims, and the design's own
  Success Criterion for this exact task is byte-identical behaviour preservation, which this
  pinned entry satisfies. No mechanical basis to attribute this to this round's deliverable —
  not flagged.
