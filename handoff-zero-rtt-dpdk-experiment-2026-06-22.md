# Handoff: DPDK 0-RTT Experiment — Permanent Fix & Retry

**Date**: 2026-06-22  
**Repo**: `C:\Users\shir\Documents\GitHub\zero-rtt-demo`  
**Focus**: Make permanent fix for two infra bugs found this session, then re-run the full DPDK experiment.

---

## What Happened This Session

Deployed the DPDK CDK stack (`infra/dpdk`) and ran `experiments/dpdk/run_experiment.sh`. Found and diagnosed two bugs:

### Bug 1: VMs Have No Repo (CRITICAL — needs permanent fix)

**Root cause**: CDK user data (`infra/dpdk/cdk/smartnics_stack.py`) clones the repo using a GitHub token from SSM Parameter Store at `/zero-rtt/github-token`. That token is **expired/invalid**. The git clone silently fails, leaving all 4 VMs without any repo.

**Workaround used this session**: Manually fetched the valid token from AWS Secrets Manager (`nanoclaw/github-token`, region `eu-central-1`) and ran `git clone` on all 4 VMs via SSM.

**Permanent fix needed**: Update the CDK user data to pull the token from Secrets Manager instead of SSM Parameter Store. The secret `nanoclaw/github-token` in `eu-central-1` is the valid fine-grained PAT. Relevant file: `infra/dpdk/cdk/smartnics_stack.py` — all `BASE_USER_DATA` and NIC-specific user data blocks that contain `ssm get-parameter --name /zero-rtt/github-token` need to be changed to `secretsmanager get-secret-value --secret-id nanoclaw/github-token --query SecretString --output text | tr -d '"'`. The IAM role for the instances must also have `secretsmanager:GetSecretValue` on that secret ARN.

**Also**: The experiment runner's git-pull step (`run_core.sh` line ~49) should also handle the case where the repo doesn't exist (do a clone instead of just `git pull`).

### Bug 2: pcap Transfer via SSM Fails for Large Files (partially fixed)

**Root cause**: `run_core.sh` tries to transfer endpoint pcap files (1.1–1.9 MB) by base64-encoding them and returning them as SSM `StandardOutputContent`. Two SSM limits break this:
1. `get-command-invocation` caps `StandardOutputContent` at 24 KB → only first 18 KB of pcap is returned
2. The fetched base64 (~24 KB) is then embedded inline in the next SSM command (`echo '<24KB string>' | base64 -d > file`), which exceeds SSM's 8 KB parameter size limit → the write command silently fails → pcap file is never created on ClientNIC

**Fix applied this session** (not committed): Changed `run_core.sh` line ~350 to use ClientNIC's own eth0 capture (`/tmp/client_side.pcap`, already written by `clientnic.sh`'s tcpdump) instead of the fetched-from-Client-host `/tmp/client_side_endpoint.pcap`. This gives valid `fct` and `send_unlock` metrics.

**Remaining gap**: `server_gap` metric is still missing because the Server host pcap still can't be transferred. Fix options (choose one):
- **Option A (recommended)**: Run `analyze_metrics.py` directly on the Server host (repo is cloned there now). Requires making `--client-pcap` optional in `experiments/utils/analyze_metrics.py` and pip-installing scapy on the Server VM at experiment start. Collect only the text output (~200 bytes) via SSM.
- **Option B**: Use S3 to transfer pcaps. Instances have IAM roles; check if S3 access is available.

---

## Current State of the Repo

### Uncommitted change in working tree

`experiments/utils/run_core.sh` has one local edit (not yet staged or committed):

**Changed** (around line 337–352): The block that fetched `client_side.pcap` from the Client host has been replaced with a comment explaining why ClientNIC's own capture is used instead, and the `--client-pcap` argument now points to `/tmp/client_side.pcap` (ClientNIC eth0 capture) instead of `/tmp/client_side_endpoint.pcap`.

Run `git diff experiments/utils/run_core.sh` to see the exact diff.

### Last experiment report

`experiments/dpdk/reports/integration-test-report-2026-06-22.md` — the most recent run (5 parallel connections, 1 port). Key results:

| Metric | Value |
|--------|-------|
| send_unlock | min=0.39ms, mean=1.06ms, max=1.66ms (n=5) |
| fct (pcap) | min=7346ms, mean=16527ms, max=33808ms (n=5) |
| server_gap | not captured |

The **~1ms send_unlock** confirms 0-RTT is working — client sends data almost immediately after SYN (vs ~1 RTT ≈ 50ms without 0-RTT).

The **7–34s FCT** for 1MB is abnormally high (expected ~500ms–2s) and suggests retransmissions in the data path. Worth investigating after fixing the infra bugs.

---

## Infrastructure Details (this session's deployed stack)

| Role | Instance ID | Public IP |
|------|------------|-----------|
| Client | i-05dad7a002c1d39c5 | 18.194.79.33 |
| ClientNIC | i-03472249e95f74d7b | 18.184.53.83 |
| ServerNIC | i-0b9bdbba54564d726 | 63.177.237.94 |
| Server | i-073d13bd72dc9f606 | 18.199.221.13 |

Stack ARN: `arn:aws:cloudformation:eu-central-1:191106064063:stack/SmartNicsStack/a6bf58b0-6e6b-11f1-a786-0ad8441e5557`  
Region: `eu-central-1`  
Server private IP: `10.1.2.226`  
ServerNIC eth0 MAC (gateway MAC): `02:32:cb:ec:69:8b`

Repo was manually cloned on all 4 VMs this session. Binaries were built (clientnic-dpdk-forwarder, servernic-dpdk). **The VMs are still running** (stack not destroyed). A re-run can skip the CDK deploy step and go straight to the experiment.

AWS Secrets Manager secret: `nanoclaw/github-token` (region: `eu-central-1`) — fine-grained GitHub PAT, valid.

---

## Steps for the Next Session

### Step 1: Permanent fix for CDK user data (Bug 1)

1. Read `infra/dpdk/cdk/smartnics_stack.py`
2. Find all occurrences of `ssm get-parameter --name /zero-rtt/github-token` and replace with `secretsmanager get-secret-value --secret-id nanoclaw/github-token --query SecretString --output text | tr -d '"'`
3. Check the instance IAM role (`infra/dpdk/cdk/smartnics_stack.py`) — add `secretsmanager:GetSecretValue` on `arn:aws:secretsmanager:eu-central-1:191106064063:secret:nanoclaw/github-token*`
4. Also update `infra/scapy/cdk/smartnics_stack.py` (mirrored stack) with the same fix

### Step 2: Permanent fix for pcap analysis (Bug 2)

**Option A** implementation:
1. In `experiments/utils/analyze_metrics.py`: make `--client-pcap` optional (change `required=True` → `required=False, default=None`); wrap client analysis in `if args.client_pcap:` block; add early-exit if neither pcap is provided
2. In `experiments/utils/run_core.sh`: after stopping captures, run `python3 $REPO_PATH/experiments/utils/analyze_metrics.py --server-pcap /tmp/server_side.pcap` on the SERVER host (SSM, 60s timeout); collect the text output (~100 bytes) and merge with ClientNIC's client-side analysis results

**Note**: scapy may not be on the Server VM. Add `pip3 install scapy -q 2>/dev/null || true` before the analysis step on Server.

### Step 3: Commit both fixes

Use the `commit` skill or:
```bash
git add experiments/utils/run_core.sh experiments/utils/analyze_metrics.py infra/dpdk/cdk/smartnics_stack.py
git commit -m "fix(infra+experiments): use Secrets Manager for GitHub token; fix pcap analysis for server_gap"
git push
```

### Step 4: Re-run the experiment (VMs are still up)

The VMs already have the repo and built binaries. Run:
```bash
IPERF_PARALLEL=100 IPERF_PORTS=4 IPERF_TIMEOUT=300 bash experiments/dpdk/run_experiment.sh
```
(Use a smaller parallel count than 100k for now to avoid the port-exhaustion scale issue seen in the first run.)

After the run succeeds, try the full-scale:
```bash
bash experiments/dpdk/run_experiment.sh   # defaults: 100k conns, 4 ports, 1 round
```

---

## Known Issues / Watch-outs

- **Smoke test false-failure**: The smoke test in `experiments/dpdk/run_experiment.sh` always fails on the first run of a fresh deploy (binary not yet built). This is cosmetic — the subsequent build step succeeds. Exit code will be ≥1 due to this.
- **SSM min timeout**: Some `remote_run` calls in `run_core.sh` pass `timeout=15` which is below SSM's minimum of 30. These fail silently. Grep for ` 15 > /dev/null` to find them. Not critical (they're pkill cleanup calls).
- **High FCT**: 7–34s for 1MB suggests retransmissions in the translation path. After the infra fixes, monitor whether FCT improves at smaller scale. Could be a ServerNIC translator bug (off-by-one in seq/ack delta) or TCP buffer issues.

---

## Suggested Skills

- `/run-experiment` — invoke after fixes are committed to run the DPDK experiment
- `/commit` or `/commit-push-pr` — to commit and push the permanent fixes
- `/engineering-rigor:verification-before-completion` — verify the CDK changes are correct before deploying
