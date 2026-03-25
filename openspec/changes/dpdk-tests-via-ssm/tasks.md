## 1. Cleanup Docker Artifacts

- [ ] 1.1 Delete `clientnic/dpdk/tests/Dockerfile`
- [ ] 1.2 Delete `clientnic/dpdk/tests/run_tests_docker.sh`

## 2. Add SSM Test Runner Script

- [ ] 2.1 Create `experiments/zero-rtt-clientnic-translate/run_dpdk_tests_ssm.sh` — discover ClientNIC instance by EC2 tag `smartnics-clientnic`, exit with error if not found
- [ ] 2.2 Add SSM build step: run `cd ~/zero-rtt-demo/clientnic/dpdk && meson setup builddir && ninja -C builddir` via `ssm_run`, exit non-zero on build failure
- [ ] 2.3 Add SSM test step: run `sudo bash ~/zero-rtt-demo/clientnic/dpdk/tests/run_dpdk_tests.sh builddir/clientnic-dpdk` via `ssm_run`, capture and print output
- [ ] 2.4 Exit the script with 0 if tests pass, non-zero if tests fail or build fails

## 3. Update Documentation

- [ ] 3.1 Update `clientnic/dpdk/tests/README.md` — replace Docker usage section with SSM-based instructions pointing to `run_dpdk_tests_ssm.sh`
- [ ] 3.2 Create `.claude/skills/zero-rtt-integration-tester/references/dpdk-tests.md` — document the DPDK test flow (prereqs, what it tests, how to run, how to interpret results)
- [ ] 3.3 Update `.claude/skills/zero-rtt-integration-tester/SKILL.md` — add a link/reference to `dpdk-tests.md` alongside the existing Scapy test references
