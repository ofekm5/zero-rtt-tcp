---
type: Wiki Entry
title: "0-RTT Experiment Agent Fleet"
description: "Three Hermes agents that let me run and read AWS experiments from my phone,"
tags: [hermes, agents]
timestamp: 2026-08-01T21:57:21+03:00
---

Source: `hermes/README.md`

# 0-RTT Experiment Agent Fleet

Three Hermes agents that let me run and read AWS experiments from my phone,
orchestrated by a self-hosted Paperclip company.

```
   Telegram (me, anywhere)
        │
   ┌────┴─────────────┬──────────────────┐
   │                  │                  │
experiment-runner  experiment-analyst  experiment-warden
  /run               /analyze             /cost
   │                  │                  │
   │ gh workflow run  │ git pull + read  │ gh workflow run
   │ run-experiment   │ ci-results/      │ aws-ops action=status
   ▼                  ▼                  ▼
   ═══════════ GitHub Actions (holds the OIDC role) ═══════════
                        │
                        ▼
                  AWS: smartnics_stack
```

## The one design rule

**No agent on this box holds AWS credentials.** Every AWS action goes through a
GitHub Actions `workflow_dispatch`, and GitHub Actions holds the OIDC role.

This is not incidental. The Hermes box is deliberately isolated from the cloud
account (`hermes-server` skill: *"Never copy AWS credentials or the user's work
SSH key onto this box"*), and an AWS key in any `.env` here silently removes that
isolation. Every `.env.EXAMPLE` in this directory says so; if you find yourself
adding one, the design has drifted.

The tradeoff bought: agents cannot probe a run mid-flight via SSM — they see
what the workflow reports and what it commits. That is a real limitation and the
reason live streaming telemetry is a separate, later piece of work.

## The three agents

| Agent | Owns | Model | Wakes |
|---|---|---|---|
| `experiment-runner` | dispatch + watch runs | Haiku 4.5 | `/run`, every 4h status check, optional weekly canary |
| `experiment-analyst` | read bundles, report findings | Sonnet 5 | `/analyze`, daily new-bundle check |
| `experiment-warden` | cost + fleet liveness | Haiku 4.5 | `/cost`, every 3h, daily heartbeat |

Budget shape: the two mechanical agents wake often and are bound to the cheapest
model; the analyst wakes rarely and gets the reasoning budget. Reversing that is
the easiest way to make this fleet cost more than it saves.

Separation is deliberate and enforced three ways — different SOUL, different
Telegram bot, different GitHub PAT scope:

- runner has `actions:write`, so it can start a paid run
- analyst has `contents:read` **only**, so it structurally cannot start one
- warden has `actions:write` but is limited to `action=status` by SOUL and config

**Known gap:** GitHub's fine-grained PATs cannot restrict *which workflow input*
is passed, so the warden's token technically permits `action=destroy`. That limit
is behavioural, not enforced. If it matters more later, the fix is a separate
status-only workflow the warden's token can reach and `aws-ops.yml` cannot.

## Install

Prerequisites on the box: `hermes`, `gh` (authenticated per-profile via each
profile's `GITHUB_TOKEN`), `git`, and a clone of this repo.

```bash
# one BotFather bot per profile — Telegram rejects concurrent polling of one token
for p in experiment-runner experiment-analyst experiment-warden; do
  export HERMES_HOME=~/.hermes-$p
  hermes profile install /path/to/zero-rtt-tcp/hermes/$p
  cp /path/to/zero-rtt-tcp/hermes/$p/.env.EXAMPLE $HERMES_HOME/.env
  # fill in $HERMES_HOME/.env — never commit it
done
```

### Verify before trusting (do not skip)

```bash
# 1. fallback_providers actually landed in the RESOLVED config, per profile.
#    Docs disagree on top-level vs nested under model:. Absent = silently ignored.
#    Load-bearing on the warden — a warden that dies instead of degrading is the
#    exact silence it exists to prevent.
for p in experiment-runner experiment-analyst experiment-warden; do
  echo "=== $p ==="; HERMES_HOME=~/.hermes-$p hermes config show | grep -A3 fallback
done

# 2. Command routing is two-sided and only holds if all three agree.
#    Each profile must own its pattern AND ignore the other two.
for p in experiment-runner experiment-analyst experiment-warden; do
  echo "=== $p ==="; HERMES_HOME=~/.hermes-$p hermes config show | grep -A5 mention_patterns
done

# 3. No AWS credential leaked into any profile.
grep -rl 'AWS_ACCESS_KEY\|AWS_SECRET\|AWS_SESSION_TOKEN' ~/.hermes-experiment-* && echo "STOP — isolation broken"

# 4. Schedules are what you think they are.
for p in experiment-runner experiment-analyst experiment-warden; do
  echo "=== $p ==="; HERMES_HOME=~/.hermes-$p hermes cron list
done
```

`experiment-runner`'s `weekly-regression-run` job ships **disabled**. It spends
real money on a schedule — turn it on deliberately, not by accident.

## Billing caveat, read before raising any schedule

All three profiles bind to the Claude subscription via `CLAUDE_CODE_OAUTH_TOKEN`.
Per the `hermes-server` skill, Claude Code OAuth through Hermes is **unofficial**
and has a known failure mode where traffic bills as Anthropic "extra usage"
credits or 429s on `monthly spend limit` instead of drawing on the subscription.

The warden is the highest-frequency profile here (every 3h). If credits start
draining or agents begin 429ing, suspect this first, check whether they fell
through to the OpenRouter fallback (that is the safety net working), and lower
the schedules before adding capacity.

## Paperclip

Paperclip is the orchestration layer: a company, an org chart of agents with
roles and **per-agent/per-project token budgets**, and issue-driven task
assignment with comment-driven wakes. The budget ceilings are the part that
matters most for this fleet — they are the only hard spend limit in the design.

Stand-up sketch (self-hosted, embedded DB or your own Postgres):

```bash
paperclipai company create --name "zero-rtt-lab" \
  --goal "Measure and improve 0-RTT TCP handshake elimination on the AWS 4-VM stack"
```

Then register the adapter in the Paperclip server registry and create one agent
per role with `adapterType: hermes_local`. Role configs are in
[`paperclip/`](paperclip/) — apply them via the UI or API.

Map: runner → engineer role, analyst → analyst role, warden → ops role. Keep the
Hermes SOUL as the authority on behaviour; Paperclip owns *what work is assigned*
and *what it may spend*, not *how the agent behaves*.

## Not yet verified

Everything below is inferred from docs and has **not** been confirmed against a
live install. Confirm before relying on any of it.

| Item | Why it's uncertain |
|---|---|
| `fallback_providers` placement | Hermes docs disagree top-level vs under `model:`. Verify step 1 above; if absent, use interactive `hermes fallback`. |
| `terminal.cwd: ${ZERO_RTT_REPO_PATH}` | `${VAR}` interpolation is documented for `config.yaml`, but this specific use in `cwd` is untested. If it resolves literally, set an absolute path. |
| Model strings | `claude-sonnet-5` / `claude-haiku-4-5-20251001` on `provider: anthropic`, and `anthropic/claude-sonnet-4.5` / `anthropic/claude-haiku-4.5` on the OpenRouter fallback. Confirm both routes accept these exact strings. |
| Paperclip adapter config keys | `model`, `maxIterations`, `timeoutSec`, `persistSession`, `enabledToolsets` come from the adapter README, not a live run. |
| `paperclipai` CLI name and flags | From third-party write-ups, not official docs. |
| Per-agent budget ceilings | Documented as existing; exact config key and enforcement semantics unconfirmed. This is the load-bearing budget control — verify it first. |
| Reading "last reported" for the heartbeat | The warden needs a way to see sibling activity. Cross-profile visibility on one box is unconfirmed; may need a shared status file. |

## Values I deliberately left blank

Three `skills.config` keys are empty on purpose. A plausible-looking invented
number is worse than a blank, because every downstream message inherits it:

- `experiment-runner.confirm_above_connections` — has a placeholder of 10000;
  set it from what a run at that scale actually costs you.
- `experiment-warden.hourly_cost_estimate` — the warden's leverage is that its
  cost claims are believable. Fill in your real blended hourly rate.
- `experiment-analyst.baseline_notes` — which prior runs are reference points and
  what run-to-run spread is normal. Without this the analyst will say a
  comparison is unavailable, which is the correct behaviour.
