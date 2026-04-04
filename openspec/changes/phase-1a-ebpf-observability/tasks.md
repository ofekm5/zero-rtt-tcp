## 1. bpftrace Scripts

- [x] 1.1 Create `observability/ebpf/tcp_state_trace.bt` — attaches to `tracepoint:sock:inet_sock_set_state`, filters by port `$1`, emits JSON lines with `ts_ns`, `src`, `dst`, `sport`, `dport`, `old_state`, `new_state` (mapped to name strings)
- [x] 1.2 Create `observability/ebpf/tcp_retransmit_trace.bt` — attaches to `tracepoint:tcp:tcp_retransmit_skb`, emits JSON lines with `ts_ns`, `src`, `dst`, `sport`, `dport`, `seq`, `state`

## 2. Trace Runner Script

- [x] 2.1 Create `observability/ebpf/run_trace.sh` with flags `--duration`, `--port`, `--output`, `--retransmits`
- [x] 2.2 Add runtime bpftrace install fallback (`which bpftrace` check → `amazon-linux-extras install -y BCC && yum install -y bpftrace`)
- [x] 2.3 Run bpftrace in background with `timeout`, write to output file, clean up process group on exit

## 3. CDK User Data

- [x] 3.1 Add `amazon-linux-extras install -y BCC` and `yum install -y bpftrace` to `base_user_data` in `infra/dpdk/cdk/smartnics_stack.py`
- [x] 3.2 Same change in `infra/scapy/cdk/smartnics_stack.py`

## 4. Experiment Orchestrator Integration

- [x] 4.1 In `experiments/zero-rtt-dpdk/run_experiment.sh`: add `ssm_bg` calls to start `run_trace.sh` on Client and Server VMs before server starts
- [x] 4.2 In `experiments/zero-rtt-dpdk/run_experiment.sh`: add `ssm_stdout` calls after captures stop to collect `/tmp/tcp_trace.jsonl` from both VMs
- [x] 4.3 In `experiments/zero-rtt-dpdk/run_experiment.sh`: append eBPF trace summary section to the report (state transitions with timestamps); treat collection failure as warning
- [x] 4.4 Repeat 4.1–4.3 for `experiments/zero-rtt-clientnic-translate/run_experiment.sh`

## 5. Node Scripts

- [x] 5.1 Create `experiments/zero-rtt-dpdk/nodes/ebpf-trace.sh` — interactive wrapper that starts `run_trace.sh --retransmits` (always traces both state + retransmits), waits for Ctrl+C, prints summary
- [x] 5.2 Create `experiments/zero-rtt-clientnic-translate/nodes/ebpf-trace.sh` — same, for Scapy stack

## 6. Verification

- [ ] 6.1 SSM into Client VM → run `bpftrace --version` → confirm installed  *(manual)*
- [ ] 6.2 Run `bpftrace -l 'tracepoint:sock:*'` → confirm `inet_sock_set_state` tracepoint exists  *(manual)*
- [ ] 6.3 Run `run_trace.sh --duration 10 --port 8080 --output /tmp/test.jsonl` on Client while `client.py` connects → verify JSON lines show `TCP_CLOSE → TCP_SYN_SENT → TCP_ESTABLISHED → TCP_FIN_WAIT1 → TCP_CLOSE`  *(manual)*
- [ ] 6.4 Run full experiment → verify eBPF trace summary appears in the generated report  *(manual)*
