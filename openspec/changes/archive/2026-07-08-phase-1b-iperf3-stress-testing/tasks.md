## 1. CDK Infrastructure

- [ ] 1.1 Add `amazon-linux-extras install -y epel` and `yum install -y iperf3` to `base_user_data` in `infra/dpdk/cdk/smartnics_stack.py`
- [ ] 1.2 Apply the same iperf3 install lines to `infra/scapy/cdk/smartnics_stack.py`

## 2. Node Scripts — DPDK Stack

- [ ] 2.1 Create `experiments/zero-rtt-dpdk/nodes/iperf3-server.sh` — kills existing iperf3, starts `iperf3 -s -p 5201 --json-output -D --logfile /tmp/iperf3_server.log`
- [ ] 2.2 Create `experiments/zero-rtt-dpdk/nodes/iperf3-client.sh` — accepts `<server-ip> [extra-flags...]`, runs `iperf3 -c $SERVER_IP -p 5201 -J "$@"`, prints JSON to stdout; include example usage comments in header

## 3. Node Scripts — Scapy Stack

- [ ] 3.1 Mirror `iperf3-server.sh` to `experiments/zero-rtt-clientnic-translate/nodes/iperf3-server.sh`
- [ ] 3.2 Mirror `iperf3-client.sh` to `experiments/zero-rtt-clientnic-translate/nodes/iperf3-client.sh`

## 4. Experiment Orchestrator

- [ ] 4.1 Create `experiments/zero-rtt-dpdk/run_iperf3_experiment.sh` — reuse `get_iid`/`get_ip` helpers from existing `run_experiment.sh`
- [ ] 4.2 Add SSM fallback: install iperf3 on Client and Server if not already present
- [ ] 4.3 Implement startup sequence: iperf3-server → ServerNIC (Scapy) → ClientNIC DPDK binary (`--port=5201`)
- [ ] 4.4 Implement 4-scenario test matrix via SSM on Client VM: single stream, `-P 4`, `-R`, `--bidir` (each 10s), saving JSON to `/tmp/iperf3_result_<scenario>.json`
- [ ] 4.5 Retrieve JSON results from Client VM via SSM `cat` and parse key metrics (throughput, retransmits, streams)
- [ ] 4.6 Write report to `experiments/zero-rtt-dpdk/reports/iperf3-report-$(date +%Y-%m-%d).md` with metrics table and raw JSON appended

## 5. Verification

- [ ] 5.1 SSM into Server VM → run `iperf3 -s`; SSM into Client VM → run `iperf3 -c <server-ip> -J`; verify JSON output returned
- [ ] 5.2 Run same client test with ClientNIC DPDK binary active (`--port=5201`) → verify connection completes (seq translation works)
- [ ] 5.3 Run `-P 4` scenario → verify all 4 flows appear in DPDK flow table log
- [ ] 5.4 Run full `run_iperf3_experiment.sh` end-to-end → verify report generated with throughput numbers for all 4 scenarios
