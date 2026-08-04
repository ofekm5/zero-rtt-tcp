# Mobile / remote ops — deploy stacks and run experiments without a desktop

Everything AWS-facing in this repo (CDK deploy/destroy, experiment orchestrators,
status checks) can be driven from GitHub Actions via `.github/workflows/aws-ops.yml`.
That makes the repo fully workable from a **Claude Code mobile/web session**, which
can edit files and `git push` but cannot run local PowerShell or hold AWS credentials.

## How it works

```
Claude Code mobile session                GitHub Actions runner            AWS eu-central-1
──────────────────────────                ─────────────────────            ────────────────
edit .claude/skills/deploy-infra/request.json ──push──►  aws-ops.yml (OIDC → IAM role) ──SSM──►  4× smartnics-* VMs
read  .claude/skills/deploy-infra/results/latest.md ◄──commit──  results + report                 CDK → CloudFormation
```

- **Auth**: GitHub OIDC federation to IAM role `zero-rtt-demo-github-actions`
  (repo variable `AWS_ROLE_ARN`). No long-lived AWS keys anywhere.
- **Trigger A (git-only, works from any Claude session)**: edit `.claude/skills/deploy-infra/request.json`,
  commit, push. The workflow runs on the pushed branch and **commits results back to
  the same branch** under `.claude/skills/deploy-infra/results/` (stable pointer: `.claude/skills/deploy-infra/results/latest.md`).
- **Trigger B (gh CLI, if available)**: `gh workflow run aws-ops.yml -f action=... -f variant=...`
  (requires the workflow file on the default branch; results also land in the
  run's step summary and as artifacts).

## Request file schema (`.claude/skills/deploy-infra/request.json`)

| field | values | notes |
|---|---|---|
| `action` | `status` \| `deploy` \| `experiment` \| `destroy` | what to run |
| `variant` | `dpdk` \| `scapy` \| `baseline` | picks `infra/<variant>` and `experiments/<variant>` (`baseline` → `experiments/baseline-tcp`) |
| `connections` | e.g. `"1"` | `CONNECTIONS` — measurement rounds (empty = script default 1) |
| `iperf_parallel` | e.g. `"100"` | `LOAD_PARALLEL` — TCP connections per round (empty = 100000) |
| `iperf_ports` | e.g. `"1"` | `LOAD_PORTS` (empty = 4) |
| `iperf_timeout` | e.g. `"120"` | `LOAD_TIMEOUT` seconds — **lower this when `iperf_parallel` is small** so failures surface fast |
| `nonce` | any string | bump it to re-run an otherwise identical request (a push needs a diff) |

## Playbook from a phone (Claude Code mobile session on this repo)

1. **Check what's running** (costs nothing if stack is down):
   - Set `.claude/skills/deploy-infra/request.json` → `{"action": "status", ...}`, bump `nonce`, commit, push.
   - Wait ~1 min, `git pull`, read `.claude/skills/deploy-infra/results/latest.md`.
2. **Deploy** the DPDK stack:
   - `{"action": "deploy", "variant": "dpdk"}`, push. Deploy takes ~10 min;
     the ClientNIC then builds DPDK 23.11 from source for **another ~15–20 min** —
     don't run an experiment until that's done.
3. **Run a smoke experiment**:
   - `{"action": "experiment", "variant": "dpdk", "connections": "1", "iperf_parallel": "100", "iperf_ports": "1", "iperf_timeout": "120"}`
   - Full-scale run: leave the iperf fields empty (100k connections, up to ~1 h).
   - Results: `git pull` → `.claude/skills/deploy-infra/results/latest.md` (summary + full report + log tail).
4. **Tear down when done** (stop the EC2 bill):
   - `{"action": "destroy", "variant": "dpdk"}`, push.

Important: experiment runs **hard-reset every VM's repo checkout to `origin/main`**
(`experiments/utils/run_core.sh`). Code changes only take effect on the VMs after
they are merged/pushed to `main` — pushing a feature branch triggers the workflow,
but the VMs still run `main`'s data-plane code.

Only one aws-ops run executes at a time (`concurrency: aws-ops`); a second push
queues behind the first.

## One-time setup (desktop, already-provisioned account)

```bash
bash .claude/skills/deploy-infra/scripts/aws-oidc-setup.sh   # OIDC provider + IAM role + AWS_ROLE_ARN repo variable
```

The role's permissions are deliberately narrow: assume `cdk-*` bootstrap roles
(deploy/destroy), `ec2:DescribeInstances`, `ssm:SendCommand` (AWS-RunShellScript only),
`ssm:GetCommandInvocation`, `cloudformation:DescribeStacks`.

## Failure triage from mobile

- Workflow red at **Configure AWS credentials** → role/variable missing: run the
  one-time setup above from a desktop.
- **Experiment exit code N** in `latest.md` → N checks failed; the committed
  `report.md` and `experiment.log` in the same `.claude/skills/deploy-infra/results/<stamp>-*/` dir contain
  the per-node logs. Diagnosis guide: `.claude/skills/run-experiment/references/troubleshooting.md`.
- **Smoke test: EAL init failed (stale DPDK lock?)** → re-run once (the orchestrator
  cleans `/var/run/dpdk` on start); if persistent, reboot the ClientNIC via a `status`
  check + manual SSM from a desktop, or destroy + redeploy.
