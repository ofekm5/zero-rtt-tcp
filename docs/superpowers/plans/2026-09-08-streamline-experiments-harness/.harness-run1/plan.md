# Plan: 2026-09-08-streamline-experiments-harness

## Summary
Collapse experiments/ from six entrypoints across four stack folders to a single parameterised run.sh with shared helpers in lib/ and VM scripts in nodes/.

## Sprints
1. Extract shared output and report helpers — tasks 1, 2
2. Rehome laptop-side and VM-side code — tasks 3, 4
3. Write single run.sh entrypoint — task 5
4. Add tests, delete old runners, wire report paths — tasks 6, 7, 8
5. Retarget workflow, skills, CLAUDE.md, and roadmap — tasks 9, 10

## Triage notes
Triage skipped: `triage-verdict: ok` found in the plan file. All 10 tasks are automatable; no manual tasks identified. taskCount = 10 exceeds the <=8 threshold for compact-collapse rules, so rules C1 and C2 are not applied. The design doc's SC2 verify command (`grep -rl '^log()' experiments/ | wc -l` = 1) is unachievable as written because node scripts (nodes/client.sh, nodes/server.sh, dpdk/clientnic.sh, dpdk/servernic.sh) and test harnesses each define their own `log()` and are not mentioned as callers in task 1. The Sprint 1 C1 criterion covers the intent of SC2 with a scoped check that verifies exactly the four runner files have their inline definition removed and experiments/lib/output.sh exists.

## Re-plan — sprint 2
Sprint 2's first attempt ended in `scope-violation`. Its `touches[]` named only
`experiments/dpdk` among the runner directories, but moving `experiments/utils/*`
breaks the `source` lines in all four `run_experiment.sh` runners, so leaving the
tree working required editing `baseline-tcp`, `proxmox` and `scapy` too. `touches[]`
now lists all four; sprint 2 `dependsOn: [1]` and runs alone, so the overlap with
sprint 1's touch list cannot race.

A second defect was in the contract, not the graph: "the moved files move
byte-identical" forbade repointing the remote command strings inside
`run_core.sh`, `endpoint.sh` and `measure.sh`, which Task 4's Outcome requires.
Obeying it shipped a harness that could not find `clientnic.sh`, `servernic.sh`,
`loadgen.py` or `analyze_metrics.py` on the VMs. The rewritten
`sprint-2/contract.md` narrows byte-identity to semantics and adds C3 (no
pre-move path survives under `experiments/`) plus C4 (the pytest suite) to catch it.

## Already done
(none)

## Blockers
(none)

```plan-meta
{
  "verdict": "ok",
  "sprints": [
    {
      "id": 1,
      "name": "Extract shared output and report helpers",
      "dependsOn": [],
      "touches": ["experiments/lib", "experiments/dpdk", "experiments/baseline-tcp", "experiments/proxmox", "experiments/scapy"]
    },
    {
      "id": 2,
      "name": "Rehome laptop-side and VM-side code",
      "dependsOn": [1],
      "touches": ["experiments/lib", "experiments/nodes", "experiments/tests", "experiments/utils", "experiments/dpdk", "experiments/baseline-tcp", "experiments/proxmox", "experiments/scapy"]
    },
    {
      "id": 3,
      "name": "Write single run.sh entrypoint",
      "dependsOn": [2],
      "touches": ["experiments/run.sh", "experiments/lib"]
    },
    {
      "id": 4,
      "name": "Add tests, delete old runners, wire report paths",
      "dependsOn": [3],
      "touches": ["experiments"]
    },
    {
      "id": 5,
      "name": "Retarget workflow, skills, CLAUDE.md, and roadmap",
      "dependsOn": [4],
      "touches": ["experiments/README.md", ".github/workflows", ".claude/skills", "CLAUDE.md", "roadmap.md"]
    }
  ],
  "manualTasks": [],
  "triage": {
    "skippedReason": "triage-verdict: ok found in docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md",
    "capabilitySpecCount": 0,
    "topLevelDirCount": 0,
    "taskCount": 10,
    "verbMix": [],
    "oneSentenceSummary": "Collapse experiments/ from six entrypoints across four stack folders to a single parameterised run.sh with shared helpers in lib/ and VM scripts in nodes/."
  }
}
```
