---
name: deploy-infra
description: Deploy or tear down the AWS CDK stacks for this project (infra/dpdk, infra/scapy) and set up the BlueField-3 DPU platform — locally via PowerShell or remotely via GitHub Actions (works from Claude Code mobile/web with no AWS credentials). Use when the user asks to deploy, destroy, or bootstrap the AWS infrastructure, trigger a deploy/experiment from a phone or CI, or set up the DPU.
---

### Deploying Infrastructure

**AWS EC2 Deployments (local desktop):**
```powershell
cd infra/dpdk         # or infra/scapy
.\deploy.ps1          # Creates/activates repo-root venv, installs deps, deploys
.\deploy.ps1 -Bootstrap  # First-time CDK bootstrap + deploy
.\destroy.ps1         # Tear down all stacks
```
Note: the DPDK stack's ClientNIC user data builds DPDK 23.11 from source (~15-20 min after deploy before the binary is ready).

**AWS EC2 Deployments (remote — no desktop / no local AWS credentials):**
Any environment that can `git push` (Claude Code mobile/web sessions, CI) can drive
deploy/destroy/experiment/status through `.github/workflows/aws-ops.yml`:
1. Edit `.claude/skills/deploy-infra/request.json` — set `action` (`deploy` | `destroy` | `experiment` | `status`)
   and `variant` (`dpdk` | `scapy` | `baseline`), bump `nonce`, commit, push.
2. Wait for the run, then `git pull` — results (stack outputs / experiment report) come
   back as a commit under `.claude/skills/deploy-infra/results/` (`.claude/skills/deploy-infra/results/latest.md` is the stable pointer).
Alternative trigger when `gh` is available: `gh workflow run aws-ops.yml -f action=deploy -f variant=dpdk`.
Full playbook, request schema, and failure triage: **`.claude/skills/deploy-infra/references/mobile-ops.md`**.
One-time AWS-side auth setup (OIDC role, already provisioned): `.claude/skills/deploy-infra/scripts/aws-oidc-setup.sh`.

**BlueField-3 DPU Setup:**
- Refer to `infra/bluefield/docs/` for architecture, DOCA Flow programming, and DPA cores
- Check `infra/bluefield/setup/` for OS image installation and driver setup
- Review example implementations in `infra/bluefield/examples/` (syn-punt, react patterns)
- Use `infra/bluefield/deployment/` for Docker-based DPU application deployment
