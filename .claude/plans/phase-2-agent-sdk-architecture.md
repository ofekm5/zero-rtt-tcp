# Plan: Phase 2 — Claude Agent SDK Architecture

> Implementation deferred — explore the Python Claude Agent SDK when Phases 1a/1b are complete. This section defines the architecture only.

## Prerequisites
- Phase 1a (eBPF observability) complete
- Phase 1b (iperf3 stress testing) complete

---

## Architecture Outline

```
agents/
  requirements.txt          # claude-agent-sdk, boto3
  tools/
    ssm.py                  # SSM wrappers: ssm_run(), ssm_bg(), get_instance_id()
    parsers.py              # iperf3 JSON parser, eBPF trace parser
  adaptive_tester.py        # Runs iperf3, reads results, decides next parameters
  chaos_agent.py            # Injects tc netem delays/loss, observes behavior
  orchestrator_agent.py     # Full experiment lifecycle across 4 VMs
  regression_agent.py       # Compares results against historical baselines
```

---

## Agent Tool Set (shared across all agents)

| Tool | Signature | Returns |
|------|-----------|---------|
| `ssm_run` | `(instance_name, command, timeout)` | stdout/stderr |
| `run_iperf3` | `(server_ip, duration, parallel, reverse, bidir, udp, bandwidth)` | JSON results |
| `start_ebpf_trace` | `(instance_name, duration, port)` | trace file path |
| `collect_ebpf_trace` | `(instance_name)` | JSON lines |
| `inject_netem` | `(instance_name, iface, delay_ms, loss_pct)` | void |
| `clear_netem` | `(instance_name, iface)` | void |

---

## Constraints

- Agents can't hold persistent connections — they issue SSM commands and read outputs
- Each invocation has a context window limit — long experiments need checkpoint/resume
- Bounded by AWS instance types for throughput ceilings (ENA bandwidth, not 0-RTT code)

---

## New Files (when implemented)

| Path | Description |
|------|-------------|
| `agents/requirements.txt` | claude-agent-sdk, boto3 |
| `agents/tools/ssm.py` | SSM wrappers |
| `agents/tools/parsers.py` | iperf3 JSON + eBPF trace parsers |
| `agents/adaptive_tester.py` | Self-adjusting iperf3 test agent |
| `agents/chaos_agent.py` | tc netem chaos injection agent |
| `agents/orchestrator_agent.py` | Full experiment lifecycle agent |
| `agents/regression_agent.py` | Historical baseline comparison agent |
