# Plan: Phase 1a — eBPF TCP Observability Layer

## Context

When running 0-RTT experiments via SSM across the 4 VMs, the TCP 3-way handshake is invisible at the application layer (`client.py`/`server.py` use stdlib sockets). The user needs kernel-level TCP visibility on Client and Server hosts.

> Only Client and Server VMs get bpftrace (they use kernel TCP). ClientNIC eth1 is DPDK-bound (no kernel TCP to trace). ServerNIC is a stateless forwarder.

**Parallel work**: Phase 1b (iperf3) is independent and can proceed simultaneously.

---

## Step 1a.1: Create bpftrace scripts

**New file: `observability/ebpf/tcp_state_trace.bt`**
- Traces `tracepoint:sock:inet_sock_set_state`
- Filters by configurable port (default 8080) via `$1` positional arg
- Outputs JSON lines: `{"ts_ns": ..., "src": ..., "dst": ..., "sport": ..., "dport": ..., "old_state": ..., "new_state": ...}`
- Maps state enum integers to names (TCP_ESTABLISHED=1, TCP_SYN_SENT=2, etc.)

**New file: `observability/ebpf/tcp_retransmit_trace.bt`**
- Traces `tracepoint:tcp:tcp_retransmit_skb`
- Same JSON line format with seq number and state

**New file: `observability/ebpf/run_trace.sh`**
- Wrapper: `--duration <sec>` `--port <port>` `--output <path>` `--retransmits` (optional)
- Runs bpftrace in background with timeout, writes to output file
- Deployable via SSM: `bash /home/ec2-user/zero-rtt-demo/observability/ebpf/run_trace.sh --duration 30 --port 8080 --output /tmp/tcp_trace.jsonl`

---

## Step 1a.2: CDK user data — install bpftrace on Client and Server VMs

**Modify: `infra/dpdk/cdk/smartnics_stack.py`** — add to `base_user_data` (after line 33):
```
"amazon-linux-extras install -y BCC",
"yum install -y bpftrace",
```

**Modify: `infra/scapy/cdk/smartnics_stack.py`** — same change to `base_user_data`

---

## Step 1a.3: Integrate into experiment orchestrators

**Modify: `experiments/zero-rtt-dpdk/run_experiment.sh`**
**Modify: `experiments/zero-rtt-clientnic-translate/run_experiment.sh`**

Add three sections:
1. **Before server start**: `ssm_bg` to start `run_trace.sh` on Client and Server VMs
2. **After captures stop**: `ssm_stdout` to collect `/tmp/tcp_trace.jsonl` from both VMs
3. **In report section**: Append eBPF trace summary (state transitions with timestamps)

Also add SSM runtime fallback install: check `which bpftrace` before tracing, install if missing.

---

## Step 1a.4: Create eBPF node scripts for manual use

**New file: `experiments/zero-rtt-dpdk/nodes/ebpf-trace.sh`**
**New file: `experiments/zero-rtt-clientnic-translate/nodes/ebpf-trace.sh`**
- Interactive wrapper for manual SSM sessions
- Starts tracing, waits for Ctrl+C, prints summary

---

## Files Summary

### New files
| Path | Description |
|------|-------------|
| `observability/ebpf/tcp_state_trace.bt` | bpftrace script for TCP state transitions |
| `observability/ebpf/tcp_retransmit_trace.bt` | bpftrace script for retransmits |
| `observability/ebpf/run_trace.sh` | Wrapper for running traces via SSM |
| `experiments/zero-rtt-dpdk/nodes/ebpf-trace.sh` | Manual eBPF trace node script (DPDK stack) |
| `experiments/zero-rtt-clientnic-translate/nodes/ebpf-trace.sh` | Manual eBPF trace node script (Scapy stack) |

### Modified files
| Path | Changes |
|------|---------|
| `infra/dpdk/cdk/smartnics_stack.py` | Add bpftrace to `base_user_data` |
| `infra/scapy/cdk/smartnics_stack.py` | Add bpftrace to `base_user_data` |
| `experiments/zero-rtt-dpdk/run_experiment.sh` | Add eBPF trace start/stop/collect sections |
| `experiments/zero-rtt-clientnic-translate/run_experiment.sh` | Same eBPF integration |

---

## Verification
- SSM into Client VM → `bpftrace --version` → confirm installed
- `bpftrace -l 'tracepoint:sock:*'` → confirm `inet_sock_set_state` exists
- Run `run_trace.sh` on Client while `client.py` connects → verify JSON lines show: `TCP_CLOSE → TCP_SYN_SENT → TCP_ESTABLISHED → TCP_FIN_WAIT1 → TCP_CLOSE`
- Run full experiment → verify eBPF traces appear in report
