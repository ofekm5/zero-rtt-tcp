# Run report — 2026-09-08-streamline-experiments-harness

**scope-violation** — 1 merged · 1 scope-violation · 3 dependency-blocked | 373 tool calls, 3 denied | 108m from first to last tool call

## Lanes

| lane | status | rounds | verify: passing per round | tool calls | denied | time |
|---|---|---|---|---|---|---|
| s1 | merged | 3 | r0 0/0 → r1 0/0 → r2 0/0 → r3 0/0 | 237 | 3 | 31m |
| s2 | scope-violation | 1 | r0 0/2 → r1 0/0 | 136 | 0 | 76m |
| s3 | dependency-blocked | 0 | — | 0 | 0 | — |
| s4 | dependency-blocked | 0 | — | 0 | 0 | — |
| s5 | dependency-blocked | 0 | — | 0 | 0 | — |

## Tool selection

| role | Bash | Edit | Grep | Read | Write |
|---|---|---|---|---|---|
| builder | 107 | 42 | 31 | 61 | 8 |
| grader | 84 | 0 | 0 | 1 | 0 |
| verifier | 39 | 0 | 0 | 0 | 0 |

Most-run commands: `grader: git show` ×20, `builder: grep -n` ×16, `builder: \` ×9, `grader: mkdir -p` ×8, `builder: git add` ×7, `grader: git log` ×7, `builder: git status` ×7, `builder: mkdir -p` ×6

## What went wrong

- Run stopped with **scope-violation** — see launch-task-runner SKILL.md for this status.

### s2 — scope-violation

- wrote outside the sprint's touches[] — re-plan
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness-s2\.harness\sprint-2`

### s3 — dependency-blocked

- a sprint it depends on did not merge
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness\.harness\sprint-3`

### s4 — dependency-blocked

- a sprint it depends on did not merge
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness\.harness\sprint-4`

### s5 — dependency-blocked

- a sprint it depends on did not merge
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness\.harness\sprint-5`

## Tokens, cost, latency

Not captured — OpenTelemetry was off for this session. See the README's Observability section to enable it for the next run.
