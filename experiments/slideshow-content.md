# 0-RTT TCP: Eliminating Handshake Latency with Intelligent Middleware

*Proof-of-concept · AWS eu-central-1 · April 2026*

---

## Slide 1 — Architecture

**4-VM chain topology, deployed on AWS via CDK**

```
Client VM → ClientNIC VM → ServerNIC VM → Server VM
10.1.0.x    10.1.0/1.x      10.1.1/2.x    10.1.2.x
```

| Component | Role |
|-----------|------|
| **Client VM** | Unmodified TCP client |
| **ClientNIC VM** | Core 0-RTT logic — intercepts SYN, sends spoofed SYN-ACK, rewrites sequence numbers |
| **ServerNIC VM** | Stateless transparent packet forwarder |
| **Server VM** | Unmodified TCP server |

*Both endpoints remain completely unmodified — transparency is the key invariant*

---

## Slide 2 — How It Works

**ClientNIC sends a spoofed SYN-ACK before the real handshake completes**

```
Client      ClientNIC       ServerNIC       Server
  │──SYN──────>│──SYN (fwd)──>│──SYN (fwd)──>│
  │<──Spoofed  │              │<──Real SYN-ACK─│
  │   SYN-ACK──│              │   (dropped)    │
  │──ACK+DATA──>│  (buffered until delta known) │
  │            │──ACK+DATA (seq rewritten)────>│
```

**Sequence number translation** keeps the server unaware:
```
delta = spoofed_ISN − real_ISN

client→server:  TCP.seq  += delta
server→client:  TCP.ack  −= delta
```

---

## Slide 3 — Tech Stack: Phase 1 — Scapy (Fast PoC)

**Goal: validate the concept quickly, iterate on protocol logic**

| Attribute | Detail |
|-----------|--------|
| Language | Python 3.8+ |
| Packet I/O | Scapy over AF_PACKET raw sockets |
| Checksum recalc | `del pkt[IP].chksum` — Scapy auto-recalculates |
| Development speed | Hours to a working prototype |
| Deployment | `pip install scapy`, runs as root |

**Why Scapy first:**
- Layer-by-layer packet construction with `/` operator is readable and debuggable
- Interactive sniff/send loop → tight feedback cycle
- Perfect for proving the sequence-number math is correct before optimizing

**Key limitation discovered:** Python GIL + per-packet syscall overhead → ~400 ms TTFB, occasional packet drops under load

**Experiment results:**

| Metric | Value |
|--------|-------|
| 0-RTT lead time | +82–177 ms per flow |
| ISN delta range | ~830M – ~3.1B across flows |

---

## Slide 4 — Tech Stack: Phase 2 — DPDK (Production-Grade Stack)

**Goal: kernel-bypass performance, deployable onto BlueField SmartNIC**

| Attribute | Detail |
|-----------|--------|
| Language | C11 |
| Server-side I/O (eth1) | DPDK 23.11 ENA PMD, busy-poll loop |
| Client-side I/O (eth0) | AF_PACKET (kernel path — client subnet) |
| Checksum recalc | `rte_ipv4_cksum()` / `rte_ipv4_udptcp_cksum()` |
| Build system | Meson + Ninja |
| Deployment | CDK user data builds DPDK 23.11 from source (~15 min) |

**Key modules:**
- `flow_table.c` — per-connection state, ISN delta, packet buffer
- `packet_processor.c` — SYN spoof+forward, SYN-ACK delta+flush
- `translator.c` — per-packet seq/ack rewriting
- `capture.c` — built-in `--server-pcap` pcap writer (tcpdump can't reach DPDK-owned eth1)

**Experiment results:**

| Metric | Value |
|--------|-------|
| 0-RTT lead time | 113–119 ms |
| c2s buffering | 2–4 packets flushed per flow ✅ |

---

## Slide 5 — DPDK Packet Flow

**Single-threaded busy-poll loop — no interrupts, no blocking waits**

```
              ┌─────────────────────────────────────────────────────┐
              │                   ClientNIC EC2                      │
              │                                                      │
              │      PCIe (ENA)                  PCIe (ENA)         │
              │          │                            │              │
              │          ▼                            ▼              │
              │     ┌─────────┐                ┌──────────┐         │
              │     │  eth0   │                │   eth1   │         │
              │     └────┬────┘                └─────┬────┘         │
              │          │                           │               │
              │     kernel ENA                  vfio-pci            │
              │     driver                      (kernel bypassed)   │
              │     interrupt-driven                 │               │
              │          │                      NIC DMA →           │
              │     socket buffer               hugepage RX ring    │
              │          │                           │               │
              │     AF_PACKET                   DPDK polls          │
              │     recvfrom()                  RX descriptor ring  │
              │                                 rx_burst(≤32)       │
              └─────────────────────────────────────────────────────┘
```

**Client side — eth0 (kernel AF_PACKET socket)**

| Step | Detail |
|------|--------|
| Socket | `AF_PACKET / SOCK_RAW / ETH_P_ALL`, bound to eth0, `O_NONBLOCK` |
| Receive | `recvfrom()` — returns 0 immediately if queue is empty |
| Dispatch | SYN-only → `proc_handle_syn` · ACK / data → `trans_c2s` |
| Send | `sendto()` on the same raw socket |

**Server side — eth1 (DPDK ENA PMD, kernel-bypass)**

| Step | Detail |
|------|--------|
| Init | 1 RX + 1 TX queue, ring size 1024, promiscuous |
| Receive | `rte_eth_rx_burst()` — drains up to 32 mbufs per iteration |
| Dispatch | SYN+ACK → `proc_handle_syn_ack` · data → `trans_s2c` |
| Send | `rte_eth_tx_burst()` |

*Why the asymmetry:* eth0 faces the client subnet where the kernel owns the NIC — AF_PACKET is the only intercept path without kernel changes. eth1 faces the server subnet where DPDK holds the NIC exclusively, enabling true kernel-bypass.

---

## Slide 6 — iperf Stress Test Suite

**14 scenarios covering every axis of the translation layer**

| # | Scenario | Key flags | What it stresses |
|---|----------|-----------|-----------------|
| 01 | Baseline single flow | `-t 10` | Throughput reference |
| 02 | Sequential ×5 connections | `-t 5` ×5 | Repeated SYN / flow-table churn |
| 03 | Parallel 4 streams | `-t 10 -P 4` | Moderate multi-stream load |
| 04 | Parallel 16 streams | `-t 10 -P 16` | High multi-stream load |
| 05 | Bulk 100 MB | `-n 100M` | Large transfer correctness |
| 06 | Bulk 30 s time-based | `-t 30` | Sustained seq-rewrite |
| 07 | Burst 20 short connections | `-n 8K` ×20 | SYN path — most relevant to 0-RTT |
| 08 | Simultaneous bidir | `-t 10 -d` | Full-duplex seq/ack rewriting |
| 09 | Sequential bidir | `-t 10 -r` | Upload then download |
| 10 | UDP flood 1 Gbps | `-u -b 1G -t 10` | NIC interrupt / buffer stress |
| 11 | UDP flood 100 Mbps | `-u -b 100M -t 10` | Moderate UDP baseline |
| 12 | Stress 32 streams / 60 s | `-t 60 -P 32` | Sustained high-concurrency load |
| 13 | Large window 256 K | `-t 10 -w 256K` | Buffering under seq-number translation |
| 14 | Large window 1 M | `-t 10 -w 1M` | Max-window buffering stress |

---

## Slide 7 — Observability: eBPF Tracing

**TCP handshake state transitions are invisible at the application layer — bpftrace fills the gap**

```json
{"ts_ns": 1097159299231, "old_state": "TCP_CLOSE",      "new_state": "TCP_SYN_SENT"}
{"ts_ns": 1097160838006, "old_state": "TCP_SYN_SENT",   "new_state": "TCP_ESTABLISHED"}
{"ts_ns": 1097435211461, "old_state": "TCP_ESTABLISHED", "new_state": "TCP_FIN_WAIT1"}
```

- `tcp_state_trace.bt` — attaches to `tracepoint:sock:inet_sock_set_state`, emits JSON per state transition
- `run_trace.sh` — SSM-deployable wrapper, auto-installs bpftrace, runs with `--duration` / `--port`
- Scoped to Client + Server VMs (ClientNIC's eth1 is DPDK-owned; ServerNIC is stateless)
- Time from `TCP_CLOSE → TCP_ESTABLISHED`: **1.5 ms** — confirms spoofed SYN-ACK reaches client immediately

**pcap capture** runs on **ClientNIC only** — ServerNIC has no capture mechanism:
- `client_side.pcap` (eth0): tcpdump on both stacks
- `server_side.pcap` (eth1): tcpdump on Scapy stack; built-in DPDK pcap writer (`capture.c --server-pcap`) on DPDK stack — tcpdump cannot access a DPDK-owned interface

---

## Slide 8 — Improvements

**Four tracks to a faster, smarter stack**

### DPDK Enhancements
- **RSS + flow-table sharding** — distribute flows across HW RX queues, one lcore per shard, no lock contention → near-linear throughput scaling with core count
- **BlueField DPA offload** — off-load SYN interception + spoofed SYN-ACK generation to DPA RISC-V cores running in parallel to the ARM pipeline; ARM handles translation → path to wire-rate 0-RTT

### s2c Packet Buffering — Fix ASAP
- Server→client packets arriving before `delta_valid` is set are silently dropped in both stacks (`trans_s2c` returns immediately with no buffer)
- c2s buffering is implemented in DPDK (`ft_buffer_pkt`) but the equivalent does not exist for the reverse direction
- Fix: add `ft_buffer_s2c_pkt` / flush on delta-set, mirroring the existing c2s mechanism — until then, connections survive only via TCP retransmit, breaking strict 0-RTT semantics

### Moving Translation Responsibility to ServerNIC
- Currently ClientNIC holds all state and rewrites every packet — a single point of complexity
- Shifting seq/ack rewriting to ServerNIC distributes the pipeline: ClientNIC focuses on SYN spoofing, ServerNIC handles ongoing translation
- Reduces per-packet work on the critical SYN interception path and opens the door to stateless ClientNIC designs

### iperf for Reliable Load Testing
- `client.py` measures TTFB for small payloads only — iperf adds throughput, concurrency, and burst coverage
- 14 scenarios already scripted (baseline, parallel streams, burst SYN flood, UDP flood, large-window)
- Next: automate full iperf suite inside `run_experiment.sh`; add `-w 256K`/`-w 1M` to confirm TCP window is the throughput bottleneck

### Chaos Agent / Fuzzer
- Inject disruption between Client and Server to stress-test 0-RTT resilience under adversarial conditions
- **DDoS simulation** — flood the ClientNIC SYN path with spoofed SYNs from random IPs to exhaust the flow table and measure degradation under connection storms
- **Man-in-the-middle** — intercept and mutate packets mid-flow (corrupt seq numbers, flip TCP flags, replay old SYN-ACKs) to verify the translation layer detects or survives tampering
- **Packet loss / reorder injection** — randomly drop or delay forwarded packets at ServerNIC to expose buffering edge cases in the ClientNIC pipeline
- Agent orchestrates attack scenarios via SSM, captures pcaps during disruption, and validates whether 0-RTT connections recover or fail gracefully
