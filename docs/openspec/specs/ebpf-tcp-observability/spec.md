### Requirement: TCP state transition tracing
The system SHALL provide a bpftrace script (`observability/ebpf/tcp_state_trace.bt`) that attaches to `tracepoint:sock:inet_sock_set_state` and emits one JSON line per state transition for connections matching a configurable port (`$1`, default 8080). Each line SHALL include: `ts_ns`, `src`, `dst`, `sport`, `dport`, `old_state`, `new_state` (as human-readable names, e.g. `TCP_ESTABLISHED`).

#### Scenario: State transition captured during connection
- **WHEN** a TCP connection to port 8080 transitions from `TCP_CLOSE` to `TCP_SYN_SENT`
- **THEN** the script emits a JSON line with matching `old_state: "TCP_CLOSE"`, `new_state: "TCP_SYN_SENT"`, and correct `src`, `dst`, `sport`, `dport`

#### Scenario: Port filter excludes other connections
- **WHEN** a TCP connection to port 9999 changes state
- **THEN** no output is emitted by the script

### Requirement: TCP retransmit tracing
The system SHALL provide a bpftrace script (`observability/ebpf/tcp_retransmit_trace.bt`) that attaches to `tracepoint:tcp:tcp_retransmit_skb` and emits one JSON line per retransmit event. Each line SHALL include: `ts_ns`, `src`, `dst`, `sport`, `dport`, `seq`, `state`.

#### Scenario: Retransmit event captured
- **WHEN** a TCP retransmit occurs for a connection to port 8080
- **THEN** the script emits a JSON line with `seq` matching the retransmitted segment and correct 5-tuple fields

### Requirement: SSM-deployable trace runner
The system SHALL provide `observability/ebpf/run_trace.sh` accepting flags `--duration <sec>`, `--port <port>`, `--output <path>`, and `--retransmits` (optional). It SHALL run bpftrace in the background, write output to the specified path, and exit after the duration elapses. If `bpftrace` is not installed, it SHALL install it before running.

#### Scenario: Trace runs for specified duration
- **WHEN** `run_trace.sh --duration 30 --port 8080 --output /tmp/tcp_trace.jsonl` is executed
- **THEN** bpftrace runs for 30 seconds, writes JSON lines to `/tmp/tcp_trace.jsonl`, then exits

#### Scenario: Runtime fallback install
- **WHEN** `bpftrace` is not present on the host and `run_trace.sh` is invoked
- **THEN** the script installs bpftrace via `amazon-linux-extras` + `yum` before starting the trace

#### Scenario: Retransmit tracing opt-in
- **WHEN** `--retransmits` flag is passed
- **THEN** `tcp_retransmit_trace.bt` runs alongside `tcp_state_trace.bt` and retransmit events appear in the output file

### Requirement: Experiment orchestrator integration
Both `experiments/dpdk/run_experiment.sh` and `experiments/scapy/run_experiment.sh` SHALL start `run_trace.sh` on Client and Server VMs before the server starts, collect `/tmp/tcp_trace.jsonl` from both VMs after captures stop, and append an eBPF trace summary (state transitions with timestamps) to the experiment report.

#### Scenario: Trace summary appears in report
- **WHEN** a full experiment run completes
- **THEN** the generated report contains a section with TCP state transitions and timestamps from both Client and Server VMs

#### Scenario: Trace failure is non-fatal
- **WHEN** bpftrace fails to start on a VM (e.g., tracepoint unavailable)
- **THEN** the experiment continues and the report notes the trace collection failure as a warning

### Requirement: CDK user-data bpftrace install
Both `infra/dpdk/cdk/smartnics_stack.py` and `infra/scapy/cdk/smartnics_stack.py` SHALL include bpftrace installation commands in `base_user_data` so that Client and Server VMs have bpftrace available after initial boot.

#### Scenario: bpftrace available after stack deploy
- **WHEN** a fresh Client or Server VM is launched from the CDK stack
- **THEN** `bpftrace --version` succeeds without manual installation

### Requirement: Manual eBPF trace node scripts
The system SHALL provide interactive node scripts (`experiments/nodes/ebpf-trace.sh`) that start tracing via `run_trace.sh`, wait for user interrupt (Ctrl+C), and print a summary of captured events.

#### Scenario: Manual trace started and summarized
- **WHEN** a developer runs `ebpf-trace.sh` in an SSM session and presses Ctrl+C after the experiment
- **THEN** the script prints a human-readable summary of TCP state transitions captured during the session
