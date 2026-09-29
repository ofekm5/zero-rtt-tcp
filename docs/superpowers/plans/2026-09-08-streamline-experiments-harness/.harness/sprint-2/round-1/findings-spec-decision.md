# Findings — spec-decision lens — sprint 2 round 1

No findings under this lens.

Checked against `docs/superpowers/specs/2026-09-08-streamline-experiments-harness-design.md`
("Key Constraints" and "Alternatives Considered #1") and Task 5.2's outcome text in
`docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`:

- STACK/TRANSPORT validated before sourcing any transport shim (no remote call on bad input) — matches.
- Error messages name the accepted values (`0rtt, baseline` / `ssm, ssh`) — matches.
- `REPO_PATH` is transport-dependent (`/home/ec2-user/zero-rtt-tcp` for ssm, `/home/user/zero-rtt-tcp` for ssh) — matches.
- `baseline`+`ssh` is not rejected by `run.sh` (no cross-combination check) — matches "must not be rejected... there is simply no lab infra for it yet."
- `STACK=0rtt` prologue over ssm resolves five MACs via EC2 API and smoke-tests the ClientNIC forwarder, replicating `dpdk/run_experiment.sh`'s logic (same filters, DeviceIndex values, smoke-test grep patterns) — matches.
- `STACK=0rtt` prologue over ssh reads MACs off the VMs with no smoke test, replicating `proxmox/run_experiment.sh` — matches.
- Exit code is the failure count on a normal run (`exit "$FAILURES"`); invalid STACK/TRANSPORT exits non-zero (2) before any remote call, consistent with "exits non-zero... without making any remote call."
- No report-writing added (correctly deferred to Task 8); the four runners are untouched (deferred to Task 7).
