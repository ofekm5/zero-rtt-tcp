## Context

The 0-RTT demo runs across 4 VMs (Client, ClientNIC, ServerNIC, Server). Client and Server use kernel TCP via Python stdlib sockets. During experiments, TCP handshake state transitions happen inside the kernel and are invisible to the application layer. bpftrace can attach to kernel tracepoints (`tracepoint:sock:inet_sock_set_state`, `tracepoint:tcp:tcp_retransmit_skb`) to emit structured events.

Only Client and Server VMs are in scope: ClientNIC's eth1 is DPDK-bound (kernel TCP bypassed), ServerNIC is a stateless forwarder with no application-level TCP state.

## Goals / Non-Goals

**Goals:**
- Add bpftrace scripts that emit JSON-line TCP state transition and retransmit events on Client and Server VMs
- Provide a `run_trace.sh` wrapper deployable via SSM (flags: `--duration`, `--port`, `--output`, `--retransmits`)
- Integrate trace start/stop/collect into both experiment orchestrators so reports include eBPF summaries
- Provide node scripts for manual interactive tracing during SSM sessions
- Install bpftrace via CDK user data so it's available at VM boot

**Non-Goals:**
- Tracing on ClientNIC or ServerNIC
- Continuous/production-grade tracing pipeline
- Parsing or alerting beyond appending a summary to experiment reports
- Handling kernel versions that lack the required tracepoints

## Decisions

### JSON-line output format
**Decision**: Each trace event is a single JSON object on one line, written to a file.
**Rationale**: Machine-parseable, easy to `cat` and `grep`, trivially appendable from background processes. The orchestrator collects the file via SSM and appends a formatted summary to the report.
**Alternative considered**: Plain text — rejected because it makes post-processing fragile.

### bpftrace positional arg for port filter
**Decision**: Port is passed as `$1` positional argument to bpftrace.
**Rationale**: Avoids maintaining separate script variants; the SSM wrapper sets it from `--port`.

### SSM runtime fallback install
**Decision**: `run_trace.sh` checks `which bpftrace` at runtime and installs it if missing, in addition to the CDK user-data install.
**Rationale**: Existing VMs deployed before this change won't have bpftrace from user data. The fallback ensures the script works without redeploying infra.

### Separate scripts for state transitions vs retransmits
**Decision**: Two `.bt` files (`tcp_state_trace.bt`, `tcp_retransmit_trace.bt`) instead of one combined script.
**Rationale**: Each attaches to a different tracepoint; keeping them separate allows running either independently and keeps each script simple and auditable.

### Node scripts always trace both state + retransmits
**Decision**: `experiments/*/nodes/ebpf-trace.sh` always passes `--retransmits` to `run_trace.sh` — no opt-in flag needed.
**Rationale**: Manual sessions benefit from the full picture; the extra script has negligible overhead. Keeping it simple (no flags) matches the interactive use case.

## Risks / Trade-offs

- **Kernel tracepoint availability** → `bpftrace -l 'tracepoint:sock:*'` may not list `inet_sock_set_state` on older kernels. Mitigation: verify during testing; Amazon Linux 2 with recent kernel should support it.
- **bpftrace install time at runtime** → fallback install adds ~30s to first-run experiments on old VMs. Mitigation: CDK user-data install eliminates this for freshly deployed stacks.
- **Background process cleanup** → `run_trace.sh` runs bpftrace in the background with a timeout; SSM session termination may leave orphan processes. Mitigation: use `timeout` + process group kill in the wrapper.
- **Port filter misses** → filtering by port means connections to other ports are invisible. Accepted: experiments use a fixed port (8080 default).

## Migration Plan

1. Deploy updated CDK stacks (`infra/dpdk` and/or `infra/scapy`) to install bpftrace on new VMs at boot.
2. For existing VMs: `run_trace.sh`'s runtime fallback install handles it automatically on first use.
3. No rollback needed — the eBPF scripts and orchestrator additions are purely additive; existing experiment behavior is unchanged if tracing fails (the orchestrator should treat trace collection as best-effort).

## Open Questions

- ~~Should trace collection failure (e.g., bpftrace not available) be a hard error or a warning in the orchestrator?~~ **Resolved**: warning only, experiment continues.
- ~~Should the node scripts also support `--retransmits` flag or always trace both?~~ **Resolved**: always trace both (hardcode `--retransmits` in node scripts).
