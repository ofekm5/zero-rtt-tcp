# Run report — 2026-09-08-streamline-experiments-harness

**completed** — 1 merged · 1 diff-budget-exceeded · 2 dependency-blocked | 165 tool calls, 3 denied | 42m from first to last tool call

## Lanes

| lane | status | rounds | verify: passing per round | tool calls | denied | time |
|---|---|---|---|---|---|---|
| s1 | merged | 1 | r0 1/4 → r1 4/4 | 80 | 1 | 10m |
| s2 | diff-budget-exceeded | 1 | r0 0/2 → r1 0/0 | 64 | 2 | 20m |
| s3 | dependency-blocked | 0 | — | 0 | 0 | — |
| s4 | dependency-blocked | 0 | — | 0 | 0 | — |

## Tool selection

| role | Bash | Edit | Glob | Grep | Read | Write |
|---|---|---|---|---|---|---|
| builder | 68 | 10 | 0 | 0 | 4 | 4 |
| grader | 32 | 0 | 0 | 0 | 0 | 0 |
| planner | 0 | 0 | 5 | 10 | 1 | 5 |
| verifier | 26 | 0 | 0 | 0 | 0 | 0 |

Most-run commands: `verifier: \` ×15, `builder: sed -n` ×6, `builder: cat -n` ×6, `grader: git diff` ×5, `grader: mkdir -p` ×4, `verifier: mkdir -p` ×3, `builder: git diff` ×3, `builder: git add` ×3

## What went wrong

- Run stopped with **completed** — see launch-task-runner SKILL.md for this status.

### s2 — diff-budget-exceeded

- one round inserted more than the diff budget — sprint under-decomposed
- Sandbox denied builder Bash `python -`: reaches outside the worktree: `ssh` in command position with no shell-function shim defined before first use
- Sandbox denied builder Bash `git commit`: reaches outside the worktree: `ssh` in command position with no shell-function shim defined before first use
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness-s2\.harness\sprint-2`

### s3 — dependency-blocked

- a sprint it depends on did not merge
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness\.harness\sprint-3`

### s4 — dependency-blocked

- a sprint it depends on did not merge
- Evidence: `C:\Users\shir\Documents\GitHub\.task-runner-worktrees\2026-09-08-streamline-experiments-harness\.harness\sprint-4`

## Tokens, cost, latency

Not captured — OpenTelemetry was off for this session. See the README's Observability section to enable it for the next run.
