## 1. Orchestrator Refactor (run_experiment.sh)

- [x] 1.1 Add `git config --global --add safe.directory /home/ec2-user/zero-rtt-demo` before each VM's `git pull` command in the orchestrator
- [x] 1.2 Replace the inline Server startup block (Step 1) with `setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/server.sh < /dev/null >> /tmp/server.log 2>&1 &` via SSM
- [x] 1.3 Replace the inline ServerNIC startup block (Step 2) with `setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/servernic.sh < /dev/null >> /tmp/servernic.log 2>&1 &` via SSM (iptables and route setup stay in the node script)
- [x] 1.4 Discover GW MAC via `ssm_stdout "$SERVERNIC_ID" "cat /sys/class/net/eth0/address"` before launching ClientNIC (this already exists — verify it is preserved)
- [x] 1.5 Replace the inline ClientNIC DPDK startup block (Task 10.3) with `SKIP_BUILD=1 setsid bash $REPO_PATH/experiments/zero-rtt-dpdk/nodes/clientnic.sh $GW_MAC < /dev/null >> /tmp/clientnic.log 2>&1 &` via SSM
- [x] 1.6 Keep the client test calling `client.py --mode repeated --count 1 --verbose` directly (not via `client.sh`) — verify this is unchanged
- [x] 1.7 Keep the build step (Task 10.1 meson+ninja) as an explicit pre-step before invoking `clientnic.sh` with `SKIP_BUILD=1`, so the orchestrator retains control over when a rebuild happens

## 2. Log Collection and Report

- [x] 2.1 After client test completes, fetch and print `/tmp/server.log`, `/tmp/servernic.log`, `/tmp/clientnic.log` from their respective VMs via SSM
- [x] 2.2 Add a report-writing step at the end of `run_experiment.sh` that writes a Markdown summary to `experiments/zero-rtt-dpdk/reports/integration-test-report-$(date +%Y-%m-%d).md` including pass/fail counts, key log excerpts, and validator output

## 3. Skill Documentation Update

- [x] 3.1 Update `.claude/skills/zero-rtt-integration-tester/SKILL.md` to document the node-script-driven DPDK flow: note that `run_experiment.sh` delegates to `nodes/*.sh`, that ClientNIC requires the GW MAC argument, and that the client runs via `client.py --mode repeated`
- [x] 3.2 Update `.claude/skills/zero-rtt-integration-tester/references/troubleshooting.md` to include the known issues: git safe.directory error, `client.sh` interactive loop bypass, GW MAC EC2 API fallback

## 4. Validation

- [ ] 4.1 Run `experiments/zero-rtt-dpdk/run_experiment.sh` end-to-end and confirm all 4 VMs start via their node scripts
- [ ] 4.2 Confirm per-VM logs appear in `/tmp/*.log` on each VM and are fetched by the orchestrator
- [ ] 4.3 Confirm report is written to `experiments/zero-rtt-dpdk/reports/`
- [ ] 4.4 Confirm `validate_0rtt_capture.py` passes (all checks: spoofed SYN-ACK, ISN delta, checksums)
