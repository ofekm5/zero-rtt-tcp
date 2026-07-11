# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Infrastructure & Platform Support

This project supports **two target platforms**:

1. **AWS EC2 VMs** (primary development target)
   - 4-VM chain: Client → ClientNIC → ServerNIC → Server
   - All VMs part of AWS CDK stack called `smartnics_stack`
   - CDK code lives in `infra/scapy/` and `infra/dpdk/`
   - Mirrored from `C:\Users\shir\Documents\GitHub\private-core-cdk-stack` (excluding gitlab runner)
   - ClientNIC and ServerNIC (`infra/dpdk/`) each run a **dual-DPDK data plane**: both endpoint-facing ports are DPDK ENA PMD (vfio-pci), addressed via explicit `--client-mac`/`--server-mac`/`--gw-mac` peer MACs. Each SmartNIC also carries a dedicated, kernel-driven **management ENI** (primary interface, never bound to vfio-pci) for SSM Session Manager access.

2. **NVIDIA BlueField-3 DPU** (new platform target)
   - Hardware-accelerated SmartNIC with DOCA/DPDK
   - Comprehensive docs in `infra/bluefield/docs/`
   - Examples: syn-punt, react, wire-example in `infra/bluefield/examples/`
   - Target: DOCA 2.x/3.x with DPDK 23.x

## Project Overview

This is a proof-of-concept demonstrating **0-RTT TCP** - a technique to eliminate the traditional 3-way handshake latency by using intelligent middleware that spoofs server responses. This allows clients to send application data immediately without waiting for the full handshake to complete, saving approximately 50-200ms (1-RTT) per connection.

**IMPORTANT**: This is an educational/demonstration project only. Not suitable for production use.

## Architecture

The system consists of 4 VMs connected in series:

```
Client VM → ClientNIC VM → ServerNIC VM → Server VM
```

### Component Responsibilities

1. **Client VM** (`src/client-app/`): Standard unmodified TCP client application
2. **ClientNIC VM** (`src/clientnic/`): **Core 0-RTT logic** — intercepts SYN packets, sends spoofed SYN-ACK, forwards SYN toward Server. DPDK implementation:
   - `src/clientnic/dpdk-forwarder/` — **T8 forwarder** (live implementation): spoof SYN-ACK + stamp V in SYN ack-num + transparent forward (translation shifted to ServerNIC)
   - `src/clientnic/scapy/` — **deprecated**: proved the idea works; not used in the live path
3. **ServerNIC VM** (`src/servernic/`): In T8 mode (live) — **sole stateful translator**: reads V from SYN ack-num, computes delta, drops real SYN-ACK, rewrites all packets. `src/servernic/scapy/` is the matching **deprecated** stateless forwarder from the same feasibility phase.
4. **Server VM** (`src/server-app/`): Standard unmodified TCP server application

### Key Technical Concepts

#### Sequence Number Translation
The ClientNIC maintains a **flow table** tracking each connection's sequence number delta:
- When SYN arrives from client → immediately send spoofed SYN-ACK with random ISN (spoofed_server_isn)
- Forward original SYN to server → receive real SYN-ACK → record real ISN (real_server_isn)
- Calculate delta: `seq_delta = spoofed_server_isn - real_server_isn`
- All client→server packets: rewrite ACK by subtracting delta
- All server→client packets: rewrite SEQ by adding delta

#### Flow Processing Pipeline

**ClientNIC handles packets in two directions:**

From Client (eth0):
1. SYN → send spoofed SYN-ACK + forward to ServerNIC
2. ACK/DATA → buffer until delta known, then rewrite SEQ and forward

From ServerNIC (eth1):
1. Real SYN-ACK → drop (already sent spoofed one), record real ISN, calculate delta
2. DATA → rewrite ACK and forward to client

**ServerNIC is stateless:**
- eth1 (from ClientNIC) → forward to eth2 (to Server)
- eth2 (from Server) → forward to eth1 (to ClientNIC)

#### Packet Modification
After rewriting sequence/acknowledgment numbers, **checksums must be recalculated**:
```python
del packet[IP].chksum
del packet[TCP].chksum
# Scapy auto-recalculates on send
```

## Technology Stack

**AWS EC2 Platform:**
- **C11 + DPDK 23.11**: DPDK implementation (`src/clientnic/dpdk-forwarder/` + `src/servernic/dpdk/`) — the live data plane
- **Python 3.8+ / Scapy**: **deprecated** — used only to prove the 0-RTT idea works (`src/clientnic/scapy/`, `src/servernic/scapy/`); not part of the live path, kept for reference
- **Linux**: Required for raw socket support and DPDK vfio-pci
- **AWS**: EC2, ENIs, CDK for infrastructure

**BlueField-3 DPU Platform:**
- **NVIDIA DOCA 2.x/3.x**: Hardware acceleration framework (DOCA Flow API, DPA cores)
- **DPDK 23.x**: Packet I/O and multi-core processing
- **C11**: DPA and host-side programming
- **P4**: Optional: Packet pipeline customization via DPL/P4

### Scapy Essentials (deprecated implementation only)

Scapy provides:
- **Packet construction**: Layer-by-layer with `/` operator: `IP(dst="10.0.0.1")/TCP(flags="S")`
- **Sniffing**: `sniff(iface="eth0", prn=handler, filter="tcp")`
- **Sending**: `sendp(packet, iface="eth0")` (Layer 2) or `send(packet)` (Layer 3)
- **Modification**: Access fields like `packet[TCP].seq`, delete checksums to force recalc

## Key Documentation

### Architecture & Design
- **`src/clientnic/README.md`**: Detailed ClientNIC implementation (0-RTT core logic)
- **`src/servernic/README.md`**: ServerNIC forwarding implementation
- **`observability/`**: eBPF observability implementation (currently disabled) — packet tracing and performance monitoring

### OpenSpec Change Tracking
- **`openspec/backlog.yaml`**: Source of truth for which changes are queued/in-progress (managed via the `spec-delivery-loop`/`backlog-manage` skills)
- **`openspec/changes/`**: Experimental spec-driven workflow for tracking development phases
  - **`full-dpdk-endpoint-interfaces/`**: Move remaining AF_PACKET endpoint interfaces to the DPDK ENA PMD on both SmartNICs
  - **`aws-to-onprem-full-dpdk-migration/`**: Migration planning from AWS to on-prem Bluefield
  - Archived changes in `openspec/changes/archive/` (includes the completed T8 ISN-ack-num translation shift, phase-1b iperf3 stress testing, and endpoint-pcap-measurement — the latter's spec was promoted to `openspec/specs/`)

### Reference
- **`.claude/skills/run-experiment/SKILL.md`**: Run-experiment skill (pick mode, run orchestrator, diagnose failures across scapy/dpdk/proxmox/baseline)
- **`.claude/skills/run-experiment/references/troubleshooting.md`**: Known issues and debugging tips
- **`.claude/skills/run-experiment/references/test-scripts.md`**: All four runners + run_core.sh, validate_0rtt_capture.py, and analyze_metrics.py reference
- **`.claude/skills/deploy-infra/SKILL.md`**: Deploy/destroy the AWS CDK stacks and BlueField-3 DPU setup pointers

### Integration Testing
- **`experiments/scapy/run_experiment.sh`**: End-to-end orchestrator for the deprecated Scapy stack (local → 4 VMs via SSM)
- **`experiments/dpdk/run_experiment.sh`**: End-to-end orchestrator for the live DPDK stack — builds binary, passes `--server-pcap` so the validator has a real eth1 capture
- **`src/clientnic/validate_0rtt_capture.py`**: pcap analysis — validates spoofed SYN-ACK, ISN delta, timing, checksums (runs on ClientNIC VM); copy to `/tmp/` before running to avoid `src/clientnic/scapy/` shadowing the `scapy` package
- **`experiments/dpdk/reports/`**: Test run reports

Startup order: **Server → ServerNIC → ClientNIC → Client**

## Development Status

**AWS EC2 Platform:**
- [x] ServerNIC stateless forwarder (`src/servernic/scapy/main.py`) — deprecated, feasibility PoC only
- [x] Client iperf traffic generator (`src/client-app/iperf_client.sh`)
- [x] Server iperf listener (`src/server-app/iperf_server.sh`)
- [x] ClientNIC Scapy implementation (`src/clientnic/scapy/`) — deprecated, feasibility PoC only
- [x] ClientNIC DPDK forwarder (`src/clientnic/dpdk-forwarder/`) — T8 variant, live: spoof + stamp V + transparent forward
- [x] ServerNIC DPDK implementation (`src/servernic/dpdk/`) — T8 sole translator, live: V extraction, delta, buffering, seq/ack rewrite
- [x] Integration test suites (`experiments/`)

**Active Work Streams (OpenSpec):**
- [x] **T8 ISN-ack-num translation**: DONE — `src/clientnic/dpdk-forwarder/` + `src/servernic/dpdk/` implement the full T8 data plane
- [x] **Endpoint-based pcap measurement**: DONE — spec promoted to `openspec/specs/endpoint-pcap-measurement/`
- [ ] **Full-DPDK endpoint interfaces**: move both SmartNICs' remaining AF_PACKET endpoint ports to the DPDK ENA PMD (`openspec/changes/full-dpdk-endpoint-interfaces/`)
- [ ] **AWS-to-OnPrem migration**: Full DPDK on Bluefield-3 DPU

**BlueField-3 DPU Platform:**
- [ ] DPU-native 0-RTT implementation (DOCA Flow + DPA)
- [ ] Comprehensive architecture & programming docs (`infra/bluefield/docs/`)
- Examples in progress (`infra/bluefield/examples/`)

## Development Workflow

**No desktop? (Claude Code mobile/web/cloud session):**
All AWS operations — deploy/destroy CDK stacks, run experiments, check status — can be
triggered without local AWS credentials via GitHub Actions (`.github/workflows/aws-ops.yml`):
edit `.claude/skills/deploy-infra/request.json`, commit, push; results come back as a commit under `.claude/skills/deploy-infra/results/`
(read `.claude/skills/deploy-infra/results/latest.md` after `git pull`). Full playbook: **`.claude/skills/deploy-infra/references/mobile-ops.md`**.

**AWS EC2 Testing & Experimentation:**
1. **DPDK stack** (live): `./experiments/dpdk/run_experiment.sh`
2. **Scapy stack** (deprecated, feasibility PoC only): `./experiments/scapy/run_experiment.sh`
3. Investigate failures using the manual steps in `.claude/skills/run-experiment/SKILL.md`
4. Reports are written automatically to `experiments/<mode>/reports/`

**Change Management (OpenSpec Workflow):**
- Active changes tracked in `openspec/backlog.yaml` + `openspec/changes/` with spec-driven proposals, designs, and task lists
- Use the `spec-planning:propose`, `spec-planning:explore`, `spec-planning:archive`, `spec-delivery-loop:backlog-manage`, and `spec-delivery-loop:spec-delivery-loop` skills
- Completed changes archived with full context preserved

## Testing Approach

### Unit Testing
- Flow table operations (create, update, lookup)
- Sequence number rewriting algorithms
- Checksum recalculation correctness

### Integration Testing
- End-to-end connection establishment
- Data transmission correctness
- Multiple concurrent connections
- Connection teardown (FIN/RST)

### Performance Testing
- Measure time-to-first-byte with/without 0-RTT
- Expected improvement: 1-RTT reduction (50-200ms depending on network latency)
- Test with simulated high-latency networks

### iperf Timeout / Parallelism Balance
See `.claude/skills/run-experiment/references/troubleshooting.md` ("IPERF_TIMEOUT / IPERF_PARALLEL Balance") — `IPERF_TIMEOUT` and `IPERF_PARALLEL` are coupled and must be kept in sync.

## Important Constraints

### Protocol Limitations
- **TCP only** (not UDP, QUIC, etc.)
- Does not handle TCP options (timestamps, window scaling, SACK)
- Assumes reliable network (no packet reordering)

### Security Warnings
- **Educational/demo use only** - not production-ready
- No encryption or authentication
- Vulnerable to packet injection in real networks
- Should only be used in isolated/controlled environments

### Implementation Notes
- Flow identification uses 4-tuple: (src_ip, src_port, dst_ip, dst_port)
- All sequence number arithmetic must use 32-bit wraparound: `& 0xFFFFFFFF`
- Client and server applications remain **completely unmodified** - transparency is key
- Packet buffering required: client may send data before real SYN-ACK arrives

## Module Structure

```
src/
├── client-app/
│   ├── iperf_client.sh     # iperf2 test-scenario suite (client side)
│   └── README.md
│
├── clientnic/
│   ├── validate_0rtt_capture.py  # pcap analysis: spoofed SYN-ACK, ISN delta, checksums
│   ├── README.md
│   ├── scapy/                    # DEPRECATED — Scapy implementation, feasibility PoC only, not used in the live path
│   │   ├── main.py               # Entry point, sniffers on eth0/eth1
│   │   ├── src/
│   │   │   ├── pipeline.py       # Parse → classify → dispatch
│   │   │   └── utils/
│   │   │       ├── flow_table.py         # Connection state and seq delta tracking
│   │   │       ├── packet_processor.py   # SYN interception, spoofed SYN-ACK, delta
│   │   │       ├── translator.py         # Seq/ack modification, checksum recalc
│   │   │       └── logger.py             # Packet logging
│   │   └── tests/                # Python unit tests
│   └── dpdk-forwarder/           # LIVE — DPDK T8 forwarder: spoof + stamp V + transparent forward
│       ├── main.c                # EAL init, CLI, busy-poll loop
│       ├── flow_table.c/h        # Slim flow table: {V, client_mac, state} — no delta or buffer
│       ├── io.c/h                # eth0 AF_PACKET + eth1 DPDK ENA port
│       ├── packet_processor.c/h  # proc_handle_syn: spoof SYN-ACK + stamp V in ack-num
│       ├── forwarder.c/h         # forward_c2s / forward_s2c: Ethernet rewrite only
│       ├── pipeline.c/h          # Parse → classify → dispatch
│       ├── checksum.c/h          # IP + TCP checksum recalc
│       ├── capture.c/h           # --server-pcap pcap writer for eth1 RX
│       ├── log.c/h               # RTE_LOG wrappers
│       ├── meson.build           # Build definition (binary: clientnic-dpdk-forwarder)
│       ├── README.md
│       └── tests/                # Python unit tests + virtual-PMD smoke tests
│
├── servernic/
│   ├── README.md
│   ├── scapy/                    # DEPRECATED — Scapy implementation, feasibility PoC only, not used in the live path
│   │   ├── main.py               # Simple packet forwarder
│   │   ├── src/
│   │   │   ├── pipeline.py       # Forwarding logic
│   │   │   └── utils/
│   │   │       └── logger.py     # Packet logging
│   │   └── tests/
│   └── dpdk/                     # LIVE — DPDK T8 sole translator implementation
│       ├── flow_table.c/h        # Hash table: {V, real_isn, delta, buffer}
│       ├── syn_handler.c/h       # SYN: extract V, zero ack, forward; SYN-ACK: set delta, flush, drop
│       ├── translator.c/h        # trans_c2s (ACK-=delta) and trans_s2c (SEQ+=delta)
│       ├── pipeline.c/h          # Parse → classify → dispatch
│       ├── io.c/h                # eth1 DPDK ENA port + eth2 AF_PACKET raw socket
│       ├── checksum.c/h          # IP + TCP checksum recalc
│       ├── log.c/h               # RTE_LOG wrappers
│       ├── meson.build           # Build definition (binary: servernic-dpdk)
│       ├── README.md
│       └── tests/                # Python unit tests (no DPDK required)
│
└── server-app/
    ├── iperf_server.sh     # iperf2 listener (server side)
    └── README.md

experiments/
├── scapy/              # Deprecated Scapy stack: run_experiment.sh + clientnic.sh/servernic.sh node scripts
├── dpdk/               # Live DPDK stack: run_experiment.sh, node scripts, probes/, reports/
├── baseline-tcp/       # Plain-TCP baseline: run_experiment.sh + reports/
├── proxmox/            # RUNS lab (Proxmox) orchestrator
├── nodes/              # Shared node scripts: server.sh, client.sh, ebpf-trace.sh
├── utils/              # run_core.sh, measure.sh, analyze_metrics.py, ssm.sh, ssh_lab.sh + tests/
└── archive/            # Historical test reports

infra/
├── baseline/           # AWS CDK stack: plain-TCP baseline (kernel-routed NIC VMs)
├── scapy/              # AWS CDK stack: deprecated Scapy data plane (Python on ClientNIC)
│   ├── deploy.ps1 / destroy.ps1
│   └── cdk/
│       ├── packet_test_stack.py   # VPC with Client/Middle/Server subnets
│       └── smartnics_stack.py     # EC2 instances, ENIs, route tables
├── dpdk/               # AWS CDK stack: live DPDK data plane (C/DPDK on ClientNIC)
│   ├── deploy.ps1 / destroy.ps1
│   └── cdk/
│       ├── packet_test_stack.py   # VPC (same topology)
│       └── smartnics_stack.py     # ClientNIC gets DPDK 23.11 + vfio-pci + binary build; VMs git-clone the repo, so paths are relative to repo root (e.g. src/servernic/dpdk)
└── bluefield/          # NVIDIA BlueField-3 DPU infrastructure and examples
    ├── docs/           # Architecture, programming, operations, development guides
    ├── examples/       # syn-punt, react, wire-example DOCA/DPDK implementations
    ├── deployment/     # Docker and BFB image setup
    └── setup/          # DPU mode configuration and scripts

observability/                # eBPF observability implementation (currently disabled)
├── ...                        # Packet tracing and performance monitoring

openspec/
├── backlog.yaml         # Source of truth for queued/in-progress changes
├── specs/                # Current-truth capability specs
├── changes/              # Experimental spec-driven change tracking
│   ├── full-dpdk-endpoint-interfaces/       # Move remaining AF_PACKET endpoint ports to DPDK ENA PMD
│   ├── aws-to-onprem-full-dpdk-migration/   # Migration planning to Bluefield
│   └── archive/          # Completed changes (DPDK port, SSM tests, T8 translation shift, phase-1b iperf3, endpoint-pcap-measurement, …)

.claude/skills/deploy-infra/    # Deploy skill + mobile/remote ops (AWS deploy/experiment/destroy via GitHub Actions)
├── SKILL.md             # Local + remote deploy instructions
├── request.json         # Edit + commit + push to trigger a run
├── results/             # Workflow-committed run results (latest.md = stable pointer)
├── references/          # mobile-ops.md — full playbook
└── scripts/             # One-time AWS OIDC setup for the GitHub Actions role

.github/workflows/aws-ops.yml   # GitHub Actions workflow backing the remote ops path

venv/                   # Shared Python venv for local dev (all components)
```

### Deploying Infrastructure
See the `deploy-infra` skill (`.claude/skills/deploy-infra/SKILL.md`) — AWS EC2 CDK deploy/destroy commands and BlueField-3 DPU setup pointers.
