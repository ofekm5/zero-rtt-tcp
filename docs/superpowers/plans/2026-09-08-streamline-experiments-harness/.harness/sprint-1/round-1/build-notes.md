# Build notes — sprint 1 round 1

Commit: `a98c4f8 harness(sprint-1): fold the baseline flow into lib/core.sh behind STACK` — touches only `experiments/lib/core.sh`.

## Changes made
- experiments/lib/core.sh:32-36 — header documents the `STACK` knob (0rtt default, baseline skips NIC steps, MACs may be "").
- experiments/lib/core.sh:76-80 — `run_experiment` reads `STACK` (unset → `0rtt`). Any value other than `0rtt`/`baseline` gets `fail` + `return 1` before any remote call.
- experiments/lib/core.sh:151-186 — baseline-only NIC pre-flight: IP-forwarding checks, the `ip route show 10.1.{2,0}.0/24` checks with the route-add fallback, and the server-process cleanup. Commands and order are copied verbatim from `baseline-tcp/run_experiment.sh` Steps 1-2, with `ssm_*` swapped for `remote_*`.
- experiments/lib/core.sh:194-279 — after `endpoint_tune`: baseline calls `wan_tune_middle_leg "$CLIENTNIC_ID" eth1 "$SERVERNIC_ID" eth0` (netem on the middle leg). 0rtt keeps the existing cleanup and both `meson setup` builds, now inside the `else`.
- experiments/lib/core.sh:297-373 — WAN_US, the ServerNIC start (`nodes/servernic.sh`) and the ClientNIC start (`nodes/clientnic.sh`) are now 0rtt-only.
- experiments/lib/core.sh:385-404 — Step 5. 0rtt: the existing NIC tcpdump/binary stop. Baseline: capture stop, then `pkill -f loadgen.py` on the Server, then `endpoint_analyze`. That is the baseline runner's order: it analyzes before reading the server log.
- experiments/lib/core.sh:416-417 — for baseline, the server-log check also accepts `connection`, as the baseline runner's regex did. The 0rtt regex is unchanged.
- experiments/lib/core.sh:424-458 — Step 7 NIC log collection (`/tmp/{client,server}nic.log`) and the 0rtt `endpoint_analyze` call are 0rtt-only. `SERVERNIC_LOG`/`CLIENTNIC_LOG` default to "".
- experiments/lib/core.sh:471-475, 488-499 — the NIC in-app TTFB block and its pass/warn checks are 0rtt-only.
- In the re-indented 0rtt blocks, continuation lines of multi-line remote command strings stay at their original column. That whitespace is part of the command string, and moving it would change the 0rtt remote calls byte-for-byte. A comment at :201-203 explains why.

## Verification commands run
- C1: contract verify command, run verbatim from the worktree root: exit 0. The round-0 transcript shows the same command at exit 1 before this change, which serves as the negative control.
- `bash -n experiments/lib/core.sh`: exit 0.
- 0rtt parity check. With the C1 stubs, extended to record `node|command|timeout` for every `remote_run`/`remote_bg`/`remote_stdout`, I recorded `run_experiment m1..m5` against `git show HEAD:experiments/lib/core.sh` and against the edited file, and diffed the two: exit 0, no differences. Both unset `STACK` and `STACK=0rtt` produce 76 calls, identical to HEAD. My first attempt, before the continuation-column fix, showed whitespace-only diffs inside 6 multi-line command strings. That is what prompted the fix.
- Baseline sequence, recorded the same way: repo sync ×4, HEAD check ×4, ip_forward ×2, route show ×2, route add ×2 (stubs return empty), server cleanup, endpoint_tune, wan_tune_middle_leg (netem 50ms on cn eth1 / sn eth0), server start (`nodes/server.sh`), listen check, capture start, load, capture stop, server `pkill loadgen.py`, endpoint_analyze, `cat /tmp/server.log`. There is no `meson`, no `nodes/*nic.sh`, and no `/tmp/*nic.log`.
- `python -m pytest experiments/tests -q`: exit 0, 74 passed.

## Open concerns
- Baseline parity with `baseline-tcp/run_experiment.sh` is by construction. I did not record a side-by-side sequence from that runner: it is a top-level script that sources `ssm.sh`, which overwrites any pre-defined stubs, so it could not be mocked with the C1 approach. Two differences from that runner already exist and are unchanged here:
  - The shared repo-sync command string's continuation lines are indented 13 spaces in `core.sh` vs 9 in the runner, so the whitespace differs.
  - The Server start uses `LOAD_PORTS=$NPORTS`, which is `LOAD_PORTS` clamped to ≥1, where the runner uses raw `$LOAD_PORTS`. They are identical for any valid value.
  
  Sprint 3's pinned baseline sequence (Task 6) should account for these.
- Baseline's `run_ttfb_measurement` label stays `Client`; the old runner passed `Baseline`. This only changes echo/pass text, not a remote call. Report wording is Task 8's.
- `CORE_SERVERNIC_LOG`/`CORE_CLIENTNIC_LOG` export as "" for baseline. The report writer (Task 8) will need to handle that.
- I left the `5.1` row in `docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md` unmarked. It is the dictated plan doc and outside this sprint's `touches`.

## Permission denials
- (none; the sandbox hook refused one Bash call that wrapped the verify command in a nested `bash -c`. I re-ran the verify directly in the Bash tool.)
