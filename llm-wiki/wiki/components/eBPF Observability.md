---
type: Wiki Entry
title: "eBPF TCP Observability"
description: "Lightweight bpftrace scripts for tracing TCP events on any of the 4 VMs."
tags: [component, observability, ebpf]
timestamp: 2026-04-09T16:39:18+03:00
---

Source: `observability/ebpf/README.md`

# eBPF TCP Observability

Lightweight bpftrace scripts for tracing TCP events on any of the 4 VMs.

## Files

| File | Purpose |
|------|---------|
| `run_trace.sh` | Orchestrator — runs one or both traces for a given duration |
| `tcp_state_trace.bt` | Traces TCP state transitions (e.g. SYN_SENT → ESTABLISHED) |
| `tcp_retransmit_trace.bt` | Traces TCP retransmit events (optional, `--retransmits` flag) |

## Usage

```bash
bash run_trace.sh --duration 30 --port 8080 --output /tmp/tcp_trace.jsonl [--retransmits]
```

Deployable via SSM (copy the command above). `bpftrace` is auto-installed via `amazon-linux-extras` if missing.

## Output Format

Each event is a JSON line written to `--output`:

**State transition** (`tcp_state_trace.bt`):
```json
{"ts_ns": 1234567890, "src": "10.0.1.5", "dst": "10.0.2.10", "sport": 54321, "dport": 8080, "old_state": "TCP_SYN_SENT", "new_state": "TCP_ESTABLISHED"}
```

**Retransmit** (`tcp_retransmit_trace.bt`):
```json
{"ts_ns": 1234567891, "src": "10.0.1.5", "dst": "10.0.2.10", "sport": 54321, "dport": 8080, "seq": 100, "state": 1}
```

## How Filtering Works

Both scripts accept a port number as `$1` (default 8080). The tracepoints fire on kernel events:

- `tracepoint:sock:inet_sock_set_state` — filtered by `protocol == 6` (TCP) and matching sport **or** dport
- `tracepoint:tcp:tcp_retransmit_skb` — filtered by matching sport **or** dport

The `seq` field in retransmit events is read directly from the `sk_buff` transport header at offset +4 (network byte order, bswap'd).
