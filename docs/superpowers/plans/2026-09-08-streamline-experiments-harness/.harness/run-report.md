# Run report — 2026-09-08-streamline-experiments-harness

**pr-pending** — 6 merged | 556 tool calls, 7 denied by sandbox, 0 by permission system | 1134m from first to last tool call

## Lanes

| lane | status | rounds | verify: passing per round | tool calls | sandbox denied | permission denied | time |
|---|---|---|---|---|---|---|---|
| s1 | merged | 1 | r0 0/0 → r1 0/0 | 75 | 3 | 0 | 15m |
| s2 | merged | 1 | r0 0/2 → r1 2/2 | 56 | 0 | 0 | 345m |
| s3 | merged | 2 | r0 0/1 → r1 1/1 → r2 1/1 | 130 | 0 | 0 | 38m |
| s4 | merged | 1 | r0 0/1 → r1 1/1 | 91 | 0 | 0 | 674m |
| s5 | merged | 1 | r0 2/4 → r1 4/4 | 62 | 3 | 0 | 11m |
| s6 | merged | 1 | r0 0/0 → r1 0/0 | 127 | 1 | 0 | 38m |

## Tool selection

| role | Bash | Edit | Glob | Grep | Read | Write |
|---|---|---|---|---|---|---|
| builder | 180 | 47 | 2 | 9 | 21 | 9 |
| grader | 179 | 0 | 0 | 0 | 6 | 0 |
| planner | 0 | 0 | 3 | 4 | 1 | 7 |
| verifier | 88 | 0 | 0 | 0 | 0 | 0 |

Most-run commands: `builder: sed -n` ×28, `grader: git show` ×24, `verifier: {` ×22, `builder: grep -n` ×22, `grader: mkdir -p` ×19, `grader: git log` ×18, `verifier: mkdir -p` ×14, `grader: cat "C:/Users/shir/.claude/agents/grader.md"` ×13

## What went wrong

- Run stopped with **pr-pending** — see launch-task-runner SKILL.md for this status.

## Tokens, cost, latency

Not captured — OpenTelemetry was off for this session. See the README's Observability section to enable it for the next run.
