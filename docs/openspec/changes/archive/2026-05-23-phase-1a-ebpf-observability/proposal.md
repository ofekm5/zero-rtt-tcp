## Why

When running 0-RTT experiments across the 4 VMs via SSM, the TCP 3-way handshake is invisible at the application layer — `client.py` and `server.py` use stdlib sockets that hide kernel TCP state. We need kernel-level TCP visibility on the Client and Server VMs to observe real handshake timing, state transitions, and retransmits during experiments.

## What Changes

- New `observability/ebpf/` directory with bpftrace scripts for TCP state transitions and retransmits
- New `run_trace.sh` wrapper for deploying traces via SSM with duration/port/output flags
- New node scripts in both experiment stacks (`ebpf-trace.sh`) for manual interactive tracing
- CDK user data updated to install `bpftrace` on Client and Server VMs at boot
- Experiment orchestrators (`run_experiment.sh`) updated to start/stop/collect eBPF traces around each test run and include trace summaries in reports

## Capabilities

### New Capabilities
- `ebpf-tcp-observability`: bpftrace scripts and runner for capturing kernel-level TCP state transitions and retransmits on Client and Server VMs, with JSON output suitable for experiment reports

### Modified Capabilities
- (none — this adds observability tooling; no existing spec-level behavior changes)

## Impact

- **New files**: `observability/ebpf/tcp_state_trace.bt`, `observability/ebpf/tcp_retransmit_trace.bt`, `observability/ebpf/run_trace.sh`, node scripts in both experiment stacks
- **Modified**: `infra/dpdk/cdk/smartnics_stack.py`, `infra/scapy/cdk/smartnics_stack.py` — add bpftrace install to `base_user_data`
- **Modified**: `experiments/zero-rtt-dpdk/run_experiment.sh`, `experiments/zero-rtt-clientnic-translate/run_experiment.sh` — add trace start/collect sections
- **Dependencies**: requires `bpftrace` on Amazon Linux 2 (via `amazon-linux-extras` + `yum`); requires kernel tracepoints `tracepoint:sock:inet_sock_set_state` and `tracepoint:tcp:tcp_retransmit_skb`
- **Scope**: Client and Server VMs only — ClientNIC eth1 is DPDK-bound (no kernel TCP), ServerNIC is a stateless forwarder
