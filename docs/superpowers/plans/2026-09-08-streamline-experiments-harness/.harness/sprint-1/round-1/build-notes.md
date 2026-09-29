# Build notes — sprint 1 round 1

## Changes made
- `git mv` (no content change beyond path strings listed below):
  - experiments/utils/run_core.sh -> experiments/lib/core.sh
  - experiments/utils/{endpoint,measure}.sh -> experiments/lib/
  - experiments/utils/{ssm,ssh_lab}.sh -> experiments/lib/transport/
  - experiments/utils/tests/* -> experiments/tests/
  - experiments/utils/{loadgen,analyze_metrics}.py -> experiments/nodes/
  - experiments/dpdk/{clientnic,servernic}.sh -> experiments/nodes/
  - experiments/utils/ (now empty) removed
- experiments/{dpdk,baseline-tcp,proxmox,scapy}/run_experiment.sh — `source` lines repointed to `../lib/{core,measure,endpoint}.sh` and `../lib/transport/{ssm,ssh_lab}.sh`; stale `experiments/utils/...` path mentions in comments/report echo strings repointed (path text only)
- experiments/lib/core.sh:250,288 — remote `setsid bash $REPO_PATH/experiments/dpdk/{servernic,clientnic}.sh` -> `experiments/nodes/...`; header comments repointed
- experiments/lib/endpoint.sh:260,271 — remote `python3 $repo/experiments/utils/analyze_metrics.py` -> `experiments/nodes/analyze_metrics.py`
- experiments/lib/measure.sh:161 — remote `python3 $repo/experiments/utils/loadgen.py` -> `experiments/nodes/loadgen.py`
- experiments/nodes/client.sh:99, experiments/nodes/server.sh:60 — `$REPO_PATH/experiments/utils/loadgen.py` -> `experiments/nodes/loadgen.py`
- experiments/nodes/clientnic.sh:12 — usage comment `cd .../experiments/dpdk` -> `experiments/nodes`
- experiments/lib/transport/ssm.sh:3, experiments/dpdk/run_stress.sh:26 — comment paths repointed
- experiments/tests/test_analyze_metrics.py, test_measure_sh.py, test_loadgen.py — module path constants now resolve under `../nodes/` or `../lib/`
- experiments/tests/test_endpoint_sh.py:29,50 — `_ENDPOINT_SH` and the relative harness argument now point at `../lib/endpoint.sh`
- experiments/tests/endpoint_mock_harness.sh:1 — header comment path

## Verification commands run
- C1: `test -f experiments/lib/core.sh -a -f experiments/lib/transport/ssm.sh -a -f experiments/lib/transport/ssh_lab.sh -a ! -d experiments/utils` — exit 0
- C2: `test -f experiments/nodes/client.sh ... -a -f experiments/nodes/analyze_metrics.py && test -z "$(ls experiments/lib/*.py 2>/dev/null)"` — exit 0
- C3: `pytest experiments/tests/ -q` — bare `pytest` is not on the builder shell's PATH (exit 127, command not found); ran the same suite as `<repo>/venv/Scripts/python.exe -m pytest experiments/tests/ -q -p no:cacheprovider` — exit 0, 70 passed
- C4: `[ "$(grep -rl '^log()' experiments/lib/ | wc -l)" -eq 1 ] && [ "$(grep -rl 'Integration Test Report' experiments/lib/ | wc -l)" -eq 1 ]` — exit 0
- Extra: `bash -n` on every moved/edited .sh — all clean; every `source "$(dirname ...)/..."` target in the four runners and core.sh resolves to an existing file
- Extra: `grep -rnE "utils|dpdk/(clientnic|servernic)" experiments --include=*.sh --include=*.py` (excluding reports/ci-results) — no matches

## Open concerns
- C3's literal command relies on `pytest` being on PATH; in this sandbox it only exists in the main checkout's venv. The command text was left unchanged.
- `experiments/scapy/{clientnic,servernic}.sh` are also VM-executed but were not moved to `nodes/`. Task 4 names only the dpdk pair, and Sprint 3 deletes `experiments/scapy/`.
- Callers outside `experiments/` still name the old paths: `.github/workflows/run-experiment.yml:182,228` (`source experiments/utils/ssm.sh`, which is functional and breaks until Sprint 4), plus `.claude/skills/run-experiment/*`, `CLAUDE.md`, `README.md`, `roadmap.md` and `docs/kb/wiki/*`. `experiments/README.md` also still cites `experiments/utils/`. These were left alone because Task 9 (Sprint 4) owns them.
- Bare mentions of the old filename `run_core.sh` (without a directory) remain in comments across the runners and lib; they were left alone because they are not path strings.
- tasks.md rows (plan doc under docs/) were not marked, since that file is outside this sprint's `experiments` touch list.
