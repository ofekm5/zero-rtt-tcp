# Plan: Phase 1b — iperf3 Stress Testing

## Context

The simple `client.py`/`server.py` pair is insufficient for stress testing. iperf3 provides parallel streams, bidirectional throughput, UDP/TCP modes, and JSON output — enabling proper load testing through the 0-RTT path.

**Parallel work**: Phase 1a (eBPF observability) is independent and can proceed simultaneously.

---

## Step 1b.1: CDK user data — install iperf3 on Client and Server VMs

**Modify: `infra/dpdk/cdk/smartnics_stack.py`** — add to `base_user_data`:
```
"amazon-linux-extras install -y epel",
"yum install -y iperf3",
```

**Modify: `infra/scapy/cdk/smartnics_stack.py`** — same change

---

## Step 1b.2: Create iperf3 node scripts

**New file: `experiments/zero-rtt-dpdk/nodes/iperf3-server.sh`**
- Kills leftover iperf3, starts `iperf3 -s -p 5201 --json-output -D --logfile /tmp/iperf3_server.log`

**New file: `experiments/zero-rtt-dpdk/nodes/iperf3-client.sh`**
- Usage: `./iperf3-client.sh <server-ip> [iperf3-flags...]`
- Runs `iperf3 -c $SERVER_IP -p 5201 -J "$@"` and outputs JSON to stdout
- Example scenarios documented in header comments: `-P 4`, `-R`, `--bidir`, `-u -b 100M`

Mirror both into `experiments/zero-rtt-clientnic-translate/nodes/`.

---

## Step 1b.3: Create iperf3 experiment orchestrator

**New file: `experiments/zero-rtt-dpdk/run_iperf3_experiment.sh`**

Orchestrates iperf3 through the 0-RTT DPDK path:
1. Discover EC2 instances (reuse `get_iid`/`get_ip` pattern)
2. Pull latest code on all VMs
3. Start iperf3 server on Server VM (port 5201)
4. Start ServerNIC (Scapy forwarder)
5. Start ClientNIC DPDK binary with **`--port=5201`** (single configurable port approach)
6. Start eBPF tracing on Client + Server (if bpftrace available)
7. Run iperf3 test matrix from Client VM:
   - Single stream TCP, 10s
   - 4 parallel streams TCP, 10s (`-P 4`)
   - Reverse mode TCP, 10s (`-R`)
   - Bidirectional TCP, 10s (`--bidir`)
8. Collect JSON results + eBPF traces + pcaps
9. Write report to `experiments/zero-rtt-dpdk/reports/iperf3-report-YYYY-MM-DD.md`

SSM runtime fallback: install iperf3 via SSM if not present.

---

## Files Summary

### New files
| Path | Description |
|------|-------------|
| `experiments/zero-rtt-dpdk/nodes/iperf3-server.sh` | iperf3 server node script (DPDK stack) |
| `experiments/zero-rtt-dpdk/nodes/iperf3-client.sh` | iperf3 client node script (DPDK stack) |
| `experiments/zero-rtt-clientnic-translate/nodes/iperf3-server.sh` | iperf3 server node script (Scapy stack) |
| `experiments/zero-rtt-clientnic-translate/nodes/iperf3-client.sh` | iperf3 client node script (Scapy stack) |
| `experiments/zero-rtt-dpdk/run_iperf3_experiment.sh` | Full iperf3 stress test orchestrator |

### Modified files
| Path | Changes |
|------|---------|
| `infra/dpdk/cdk/smartnics_stack.py` | Add iperf3 to `base_user_data` |
| `infra/scapy/cdk/smartnics_stack.py` | Add iperf3 to `base_user_data` |

---

## Execution Order (Phase 1a + 1b combined)
1. CDK changes (1a.2 + 1b.1 — batch together, same files)
2. New scripts (1a.1 + 1a.4 + 1b.2 — parallel, independent)
3. Orchestrator integration (1a.3 + 1b.3)
4. Verification on live VMs

---

## Verification
- SSM into Server → `iperf3 -s`, SSM into Client → `iperf3 -c <server-ip> -J` → verify JSON output
- Run same test with ClientNIC DPDK binary running (`--port=5201`) → verify connection completes (seq translation works under load)
- Run `-P 4` parallel streams → verify all 4 flows appear in DPDK flow table log
- Run full `run_iperf3_experiment.sh` → verify report generated with throughput numbers
