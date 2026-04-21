# zero-rtt-demo

Proof-of-concept demonstrating **0-RTT TCP** — eliminating the 3-way handshake latency by using intelligent middleware (ClientNIC) that spoofs server SYN-ACKs, allowing clients to send application data immediately without waiting for the real handshake to complete (~50-200ms saved per connection).

**Educational/demo use only. Not suitable for production.**

## Architecture

```
Client VM → ClientNIC VM → ServerNIC VM → Server VM
10.1.0.x     10.1.0.x        10.1.1.x      10.1.2.x
             (eth0/eth1)     (eth0/eth1)
```

| Component | Role |
|-----------|------|
| `client-app/` | Standard unmodified TCP client |
| `clientnic/` | Core 0-RTT logic — intercepts SYN, sends spoofed SYN-ACK, rewrites sequence numbers |
| `servernic/` | Stateless transparent packet forwarder |
| `experiments/` | Experiment scripts and test reports |
| `server-app/` | Standard unmodified TCP server |
| `infra/` | AWS CDK stacks that provision the 4-VM topology |

## Packet Flow

**ClientNIC has two implementations** — Scapy (Python, `clientnic/scapy/`) and DPDK (C, `clientnic/dpdk/`) — both producing identical 0-RTT behavior.

```
Client VM          ClientNIC VM        ServerNIC VM        Server VM
    │                    │                    │                    │
    │ ① SYN              │                    │                    │
    │───────────────────>│                    │                    │
    │                    │ ② SYN (forwarded)  │                    │
    │                    │───────────────────>│ ③ SYN (forwarded)  │
    │                    │                    │───────────────────>│
    │ ④ Spoofed SYN-ACK  │                    │                    │
    │<───────────────────│                    │ ⑤ Real SYN-ACK     │
    │                    │                    │<───────────────────│
    │ ⑥ ACK + DATA (early│                    │    (dropped)       │
    │───────────────────>│                    │                    │
    │                    │ ⑦ ACK+DATA         │                    │
    │                    │  (seq rewritten)   │                    │
    │                    │───────────────────>│ ⑧ ACK+DATA         │
    │                    │                    │───────────────────>│
    │                    │                    │ ⑨ Server response  │
    │                    │ ⑩ Response         │<───────────────────│
    │                    │  (ack rewritten)   │                    │
    │ ⑪ Response         │<───────────────────│                    │
    │<───────────────────│                    │                    │
```

**Key**: ClientNIC sends the spoofed SYN-ACK (④) before the real one (⑤) even arrives, so the client can send data (⑥) a full RTT earlier than normal TCP. The real SYN-ACK is dropped; sequence numbers are transparently rewritten (⑦, ⑩) so the server never knows.

## Sequence Number Translation

ClientNIC maintains a flow table with a per-connection `seq_delta`:

```
delta = spoofed_server_isn - real_server_isn   (mod 2^32)

client→server packets:  TCP.seq += delta
server→client packets:  TCP.ack -= delta
```

After rewriting, checksums are recalculated — automatically by Scapy (`del pkt[IP].chksum`), or explicitly in C via DPDK's `rte_ipv4_cksum()` / `rte_ipv4_udptcp_cksum()`.

## Infrastructure

Two AWS CDK stacks in `infra/`, both provisioning the same 4-VM chain topology in `eu-central-1`:

| Stack | ClientNIC data plane | Directory |
|-------|---------------------|-----------|
| Scapy | Python + Scapy (AF_PACKET) | `infra/scapy/` |
| DPDK | C + DPDK 23.11 ENA PMD | `infra/dpdk/` |

Both stacks share:
- **VPC** `10.1.0.0/16` with 3 public subnets: `Client` (`10.1.0.0/24`), `Middle` (`10.1.1.0/24`), `Server` (`10.1.2.0/24`)
- **4 EC2 instances** with source/dest check disabled on NIC VMs
- **SSM access** for all instances (no bastion or SSH key needed)
- **ip_forward=1** set persistently via sysctl.conf on NIC VMs at boot

```powershell
cd infra/dpdk      # or infra/scapy
.\deploy.ps1            # Creates venv, installs CDK deps, deploys
.\deploy.ps1 -Bootstrap # First-time CDK bootstrap + deploy
.\destroy.ps1           # Tear down all stacks
```

## Running the Tests

**Scapy stack** (ClientNIC uses Python/Scapy):
```bash
./experiments/zero-rtt-clientnic-translate/run_experiment.sh
```

**DPDK stack** (ClientNIC uses C/DPDK):
```bash
./experiments/zero-rtt-dpdk/run_experiment.sh
```

Both scripts discover all 4 VMs via AWS SSM, pull latest code, rebuild if needed, start services in the correct order, run a client connection, capture packets, and validate 0-RTT behavior with `validate_0rtt_capture.py`. Exit code = number of failures.

### iperf Stress Testing

An iperf (v2) alternative to `client.py` / `server.py` is available for load and stress testing. The 0-RTT translation layer is traffic-agnostic — iperf flows pass through ClientNIC unchanged.

**Manual run (DPDK stack):** see `experiments/zero-rtt-dpdk/run_manual_steps_iperf.sh` for the 4-terminal reference. Node scripts:

| Script | VM | What it does |
|--------|----|--------------|
| `experiments/zero-rtt-dpdk/nodes/server_iperf.sh` | Server | Starts persistent `iperf -s` on port 5001 |
| `experiments/zero-rtt-dpdk/nodes/client_iperf.sh` | Client | Auto-discovers server IP, runs full suite |

**Test scenarios** (`client-app/iperf_client.sh`):

| # | Scenario | Key flags | Purpose |
|---|----------|-----------|---------|
| 01 | Baseline single flow | `-t 10` | Throughput reference |
| 02 | Sequential connections ×5 | `-t 5` ×5 loops | Repeated SYN / flow-table churn |
| 03 | Parallel 4 streams | `-t 10 -P 4` | Moderate multi-stream load |
| 04 | Parallel 16 streams | `-t 10 -P 16` | High multi-stream load |
| 05 | Bulk 100 MB | `-n 100M` | Large transfer correctness |
| 06 | Bulk 1 GB | `-n 1G` | Sustained seq-rewrite under bulk data |
| 07 | Burst — 100 short conns | `-n 64K` ×100 loops | Hammers SYN path; most relevant to 0-RTT |
| 08 | Simultaneous bidir | `-t 10 -d` | Full-duplex seq/ack rewriting |
| 09 | Sequential bidir | `-t 10 -r` | Upload then download |
| 10 | UDP flood 1 Gbps | `-u -b 1G -t 10` | NIC interrupt / buffer stress |
| 11 | UDP flood 100 Mbps | `-u -b 100M -t 10` | Moderate UDP baseline |
| 12 | Stress 32 streams / 60 s | `-t 60 -P 32` | Sustained high-concurrency load |
| 13 | Large window 256 K | `-t 10 -w 256K` | Buffering under seq-number translation |
| 14 | Large window 1 M | `-t 10 -w 1M` | Max-window buffering stress |

Results are saved as text files in `/tmp/iperf_results/` on the Client VM, with a throughput summary printed at the end.

## Quick Start (manual, on the VMs)

Startup order: **Server → ServerNIC → ClientNIC → Client**

```bash
# 1. Server VM
setsid python3 server-app/server.py --host 0.0.0.0 --port 8080 --verbose < /dev/null >> /tmp/server.log 2>&1 &

# 2. ServerNIC VM
setsid python3 servernic/scapy/main.py < /dev/null >> /tmp/servernic.log 2>&1 &

# 3a. ClientNIC VM — Scapy
setsid python3 clientnic/scapy/main.py < /dev/null >> /tmp/clientnic.log 2>&1 &

# 3b. ClientNIC VM — DPDK (eth1 must already be bound to vfio-pci)
GW_MAC=$(ssh servernic cat /sys/class/net/eth0/address)
setsid ./clientnic/dpdk/builddir/clientnic-dpdk -l 0 -- \
    --port=8080 --gw-mac=$GW_MAC --server-pcap=/tmp/server_side.pcap \
    < /dev/null >> /tmp/clientnic.log 2>&1 &

# 4. Client VM
python3 client-app/client.py --host <server-ip> --port 8080 --mode repeated --count 3 --verbose
```

> All VMs: connect via `aws ssm start-session --target <instance-id> --region eu-central-1`

## Success Criteria

| Check | Expected |
|-------|----------|
| Connections | 3/3 succeed |
| Spoofed SYN-ACK | Arrives at client before real SYN-ACK |
| ISN delta | Non-zero, consistent across all packets |
| Checksums | Zero bad checksums on eth0 and eth1 |
| Flow table | delta logged for every connection |

## eBPF Observability

TCP handshake state transitions happen inside the kernel and are invisible to `client.py` / `server.py`. The `observability/ebpf/` directory provides bpftrace scripts that attach to kernel tracepoints and emit structured JSON-line events.

**Files:**
- `tcp_state_trace.bt` — attaches to `tracepoint:sock:inet_sock_set_state`, emits one JSON line per TCP state transition (with `ts_ns`, `src`, `dst`, `sport`, `dport`, `old_state`, `new_state`)
- `tcp_retransmit_trace.bt` — attaches to `tracepoint:tcp:tcp_retransmit_skb`, emits one JSON line per retransmit
- `run_trace.sh` — bash wrapper for SSM deployment; accepts `--duration`, `--port`, `--output`, `--retransmits`; installs bpftrace automatically if missing

**How it works:**

```
tcp_state_trace.bt   ← bpftrace DSL (the eBPF logic, compiled to bytecode at runtime)
       ↑
bpftrace runtime     ← compiles .bt → eBPF bytecode, loads into kernel
       ↑
run_trace.sh         ← bash wrapper (install check, flags, timeout, background)
       ↑
run_experiment.sh    ← orchestrator (SSM deploy, collect output, append to report)
```

**Scope:** Client and Server VMs only. ClientNIC's eth1 is DPDK-bound (kernel TCP bypassed); ServerNIC is a stateless forwarder with no application TCP state.

The experiment orchestrators start `run_trace.sh` before each test, collect `/tmp/tcp_trace.jsonl` afterwards, and append a TCP state transition summary to the report. Trace failure is non-fatal — the experiment continues with a warning.

## Constraints

- TCP only (no UDP, QUIC)
- Does not handle TCP options (timestamps, window scaling, SACK)
- No encryption or authentication — isolated/controlled environments only
- Assumes reliable network (no packet reordering)

## Technology Stack

| Layer | Scapy implementation | DPDK implementation |
|-------|---------------------|---------------------|
| Language | Python 3.8+ | C11 |
| Packet I/O | Scapy (AF_PACKET) | DPDK ENA PMD + AF_PACKET |
| Checksums | Scapy auto-recalc | `rte_ipv4_cksum()` / `rte_ipv4_udptcp_cksum()` |
| eth1 capture | `tcpdump` | Built-in `--server-pcap` pcap writer |

Infrastructure: AWS CDK v2 (Python), eu-central-1
