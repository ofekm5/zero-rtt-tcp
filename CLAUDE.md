# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Response Conciseness Guidelines

**Core Principle**: Keep non-code responses concise and focused on actionable information, push changes directly to main branch.

**Response Length Rules**:
- Maximum 3-4 paragraphs for non-code responses
- Code examples, diffs, and technical output are exempt from length limits
- Focus on key findings with clear next steps

**Avoid Verbosity Patterns**:
- Repetitive context or background information
- Phrases like "as I mentioned", "previously", "to recap"
- Multiple paragraphs when bullet points would be more effective
- Describing what you'll do instead of just doing it
- Unnecessary explanations when direct answers suffice

**Preferred Format**:
- Lead with actionable information and new insights
- Use bullet points for lists instead of prose
- Combine related points into fewer paragraphs
- Focus on "what" and "next steps" rather than lengthy "why" explanations

## Infrastructure & Platform Support

This project supports **two target platforms**:

1. **AWS EC2 VMs** (primary development target)
   - 4-VM chain: Client → ClientNIC → ServerNIC → Server
   - All VMs part of AWS CDK stack called `smartnics_stack`
   - CDK code lives in `infra/scapy/` and `infra/dpdk/`
   - Mirrored from `C:\Users\shir\Documents\GitHub\private-core-cdk-stack` (excluding gitlab runner)

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

1. **Client VM** (`client-app/`): Standard unmodified TCP client application
2. **ClientNIC VM** (`clientnic/`): **Core 0-RTT logic** — intercepts SYN packets, sends spoofed SYN-ACK, forwards SYN toward Server. Two DPDK variants:
   - `clientnic/dpdk/` — **full-owner**: spoof SYN-ACK + manage all seq/ack translation (original implementation)
   - `clientnic/dpdk-forwarder/` — **T8 forwarder**: spoof SYN-ACK + stamp V in SYN ack-num + transparent forward (translation shifted to ServerNIC)
3. **ServerNIC VM** (`servernic/`): In T8 mode — **sole stateful translator**: reads V from SYN ack-num, computes delta, drops real SYN-ACK, rewrites all packets. In legacy mode — stateless Scapy forwarder.
4. **Server VM** (`server-app/`): Standard unmodified TCP server application

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
- **Python 3.8+**: Scapy implementation and all supporting tools
- **C11 + DPDK 23.11**: DPDK implementation (`clientnic/dpdk/`)
- **Scapy**: Packet manipulation library (wraps AF_PACKET raw sockets)
- **Linux**: Required for raw socket support and DPDK vfio-pci
- **AWS**: EC2, ENIs, CDK for infrastructure

**BlueField-3 DPU Platform:**
- **NVIDIA DOCA 2.x/3.x**: Hardware acceleration framework (DOCA Flow API, DPA cores)
- **DPDK 23.x**: Packet I/O and multi-core processing
- **C11**: DPA and host-side programming
- **P4**: Optional: Packet pipeline customization via DPL/P4

### Scapy Essentials

Scapy provides:
- **Packet construction**: Layer-by-layer with `/` operator: `IP(dst="10.0.0.1")/TCP(flags="S")`
- **Sniffing**: `sniff(iface="eth0", prn=handler, filter="tcp")`
- **Sending**: `sendp(packet, iface="eth0")` (Layer 2) or `send(packet)` (Layer 3)
- **Modification**: Access fields like `packet[TCP].seq`, delete checksums to force recalc

## Key Documentation

### Architecture & Design
- **`.claude/context/architecture.md`**: Complete system architecture, requirements, protocol flow
- **`clientnic/README.md`**: Detailed ClientNIC implementation (0-RTT core logic)
- **`servernic/README.md`**: ServerNIC forwarding implementation
- **`todos/tech-improvements.md`**: T8 ISN-passing technique (ack-num field piggybacking) — recommended for current AWS VPC topology

### OpenSpec Change Tracking
- **`openspec/changes/`**: Experimental spec-driven workflow for tracking development phases
  - **`t8-isn-ack-num-translation-shift/`**: T8 ISN-passing — implementation complete in `clientnic/dpdk-forwarder/` + `servernic/dpdk/`; pending probe verification on live AWS
  - **`aws-to-onprem-full-dpdk-migration/`**: Migration planning from AWS to on-prem Bluefield
  - **`phase-1a-ebpf-observability/`** & **`phase-1b-iperf3-stress-testing/`**: Phase-1 initiatives
  - Archived changes in `openspec/changes/archive/`

### Reference
- **`.claude/skills/scapy-development/SKILL.md`**: Scapy skill routing index — points to modular reference files:
  - `references/parse-decide-modify.md`: Core architectural pattern (always read alongside others)
  - `references/sending.md`: `sendp()` vs `send()`, cross-subnet forwarding
  - `references/kernel-integration.md`: AF_PACKET, RST suppression, re-capture loop
  - `references/seq-rewriting-and-checksums.md`: Delta math, checksums, 32-bit wraparound
  - `references/packet-construction.md`: Packet building, field access, flags
  - `references/sniffing.md`: `sniff()` params, BPF filters, multi-interface threading
  - `references/forging-and-spoofing.md`: Spoofed SYN-ACK, ISN generation
  - `references/pcap-analysis.md`: rdpcap/wrpcap, manual checksum verification
  - `references/unit-testing.md`: Real packets in tests, mock patterns
- **`.claude/skills/zero-rtt-integration-tester/SKILL.md`**: Integration tester skill (run tests, diagnose failures)
- **`.claude/skills/zero-rtt-integration-tester/references/troubleshooting.md`**: Known issues and debugging tips
- **`.claude/skills/zero-rtt-integration-tester/references/test-scripts.md`**: run_all.sh and analyze_capture.py reference

### Integration Testing
- **`experiments/zero-rtt-clientnic-translate/run_experiment.sh`**: End-to-end orchestrator for the Scapy stack (local → 4 VMs via SSM)
- **`experiments/zero-rtt-dpdk/run_experiment.sh`**: End-to-end orchestrator for the DPDK stack — builds binary, passes `--server-pcap` so the validator has a real eth1 capture
- **`clientnic/validate_0rtt_capture.py`**: pcap analysis — validates spoofed SYN-ACK, ISN delta, timing, checksums (runs on ClientNIC VM); copy to `/tmp/` before running to avoid `clientnic/scapy/` shadowing the `scapy` package
- **`experiments/zero-rtt-clientnic-translate/reports/`**: Test run reports

Startup order: **Server → ServerNIC → ClientNIC → Client**

### Agent System Prompts
Specialist agent prompts under `.claude/context/agents-system-prompts/`:
- **`clientnic-developer.md`**: ClientNIC 0-RTT logic developer agent
- **`servernic-developer.md`**: ServerNIC forwarder developer agent
- **`integration-tester.md`**: Integration testing agent

## Development Status

**AWS EC2 Platform:**
- [x] ServerNIC stateless forwarder (`servernic/scapy/main.py`)
- [x] Client TCP application (`client-app/client.py`)
- [x] Server TCP application (`server-app/server.py`)
- [x] ClientNIC Scapy implementation (`clientnic/scapy/`)
- [x] ClientNIC DPDK implementation (`clientnic/dpdk/`) — C11, DPDK 23.11 ENA PMD, all checks pass
- [x] ClientNIC DPDK forwarder (`clientnic/dpdk-forwarder/`) — T8 variant: spoof + stamp V + transparent forward
- [x] ServerNIC DPDK implementation (`servernic/dpdk/`) — T8 sole translator: V extraction, delta, buffering, seq/ack rewrite
- [x] Integration test suites (`experiments/`)

**Active Work Streams (OpenSpec):**
- [x] **T8 ISN-ack-num translation**: DONE — `clientnic/dpdk-forwarder/` + `servernic/dpdk/` implement the full T8 data plane (pending: probe verification + build on live AWS)
- [ ] **AWS-to-OnPrem migration**: Full DPDK on Bluefield-3 DPU
- [ ] **Phase-1b**: iperf3 stress testing and performance validation

**BlueField-3 DPU Platform:**
- [ ] DPU-native 0-RTT implementation (DOCA Flow + DPA)
- [ ] Comprehensive architecture & programming docs (`infra/bluefield/docs/`)
- Examples in progress (`infra/bluefield/examples/`)

## Development Workflow

**AWS EC2 Testing & Experimentation:**
1. **Scapy stack**: `./experiments/zero-rtt-clientnic-translate/run_experiment.sh`
2. **DPDK stack**: `./experiments/zero-rtt-dpdk/run_experiment.sh`
3. Investigate failures using the manual steps in `.claude/skills/zero-rtt-integration-tester/SKILL.md`
4. File findings in `experiments/zero-rtt-clientnic-translate/reports/`

**Change Management (OpenSpec Workflow):**
- Active changes tracked in `openspec/changes/` with spec-driven proposals, designs, and task lists
- Use `/openspec-propose`, `/openspec-explore`, `/openspec-apply-change`, and `/openspec-archive-change` skills
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
client-app/
├── client.py           # Standard TCP client
├── README.md
└── tests/
    └── test_client.py  # Client unit tests

clientnic/
├── validate_0rtt_capture.py  # pcap analysis: spoofed SYN-ACK, ISN delta, checksums
├── README.md
├── scapy/                    # Scapy-based implementation (complete)
│   ├── main.py               # Entry point, sniffers on eth0/eth1
│   └── src/
│       ├── handlers.py       # SYN interception, 0-RTT logic
│       ├── flow_table.py     # Connection state and seq delta tracking
│       ├── rewriter.py       # Seq/ack modification, checksum recalc
│       ├── spoofer.py        # Spoofed SYN-ACK generation
│       └── logger.py         # Packet logging
├── dpdk/                     # DPDK full-owner implementation (complete) — spoof + translate
│   ├── main.c                # EAL init, CLI, busy-poll loop
│   ├── flow_table.c/h        # Connection state, ISN delta, packet buffer
│   ├── io.c/h                # eth0 AF_PACKET + eth1 DPDK ENA port
│   ├── packet_processor.c/h  # SYN spoof+forward, SYN-ACK delta+flush
│   ├── translator.c/h        # Per-packet seq/ack rewriting
│   ├── pipeline.c/h          # Parse Ethernet/IP/TCP, classify, dispatch
│   ├── checksum.c/h          # IP + TCP checksum recalc via DPDK helpers
│   ├── capture.c/h           # --server-pcap pcap writer for eth1 RX
│   ├── log.c/h               # RTE_LOG wrappers
│   ├── meson.build           # Build definition
│   └── README.md
└── dpdk-forwarder/           # DPDK T8 forwarder variant (complete) — spoof + stamp V + transparent forward
    ├── flow_table.c/h        # Slim flow table: {V, client_mac, state} — no delta or buffer
    ├── io.c/h                # eth0 AF_PACKET + eth1 DPDK ENA port
    ├── packet_processor.c/h  # proc_handle_syn: spoof SYN-ACK + stamp V in ack-num
    ├── forwarder.c/h         # forward_c2s / forward_s2c: Ethernet rewrite only
    ├── pipeline.c/h          # Parse → classify → dispatch
    ├── checksum.c/h          # IP + TCP checksum recalc
    ├── log.c/h               # RTE_LOG wrappers
    ├── meson.build           # Build definition (binary: clientnic-dpdk-forwarder)
    ├── README.md
    └── tests/                # Python unit tests (no DPDK required)

servernic/
├── README.md
├── scapy/                    # Scapy-based implementation (complete, legacy)
│   ├── main.py               # Simple packet forwarder
│   └── src/
│       ├── forwarder.py      # Forwarding logic
│       └── logger.py         # Packet logging
└── dpdk/                     # DPDK T8 translator implementation (complete)
    ├── flow_table.c/h        # Hash table: {V, real_isn, delta, buffer}
    ├── syn_handler.c/h       # SYN: extract V, zero ack, forward; SYN-ACK: set delta, flush, drop
    ├── translator.c/h        # trans_c2s (ACK-=delta) and trans_s2c (SEQ+=delta)
    ├── pipeline.c/h          # Parse → classify → dispatch
    ├── io.c/h                # eth1 DPDK ENA port + eth2 AF_PACKET raw socket
    ├── checksum.c/h          # IP + TCP checksum recalc
    ├── log.c/h               # RTE_LOG wrappers
    ├── meson.build           # Build definition (binary: servernic-dpdk)
    ├── README.md
    └── tests/                # Python unit tests (no DPDK required)

experiments/
├── zero-rtt-clientnic-translate/
│   ├── run_experiment.sh       # Scapy stack end-to-end orchestrator (local → 4 VMs via SSM)
│   └── reports/                # Test run reports (e.g. integration-test-report-YYYY-MM-DD.md)
└── zero-rtt-dpdk/
    └── run_experiment.sh       # DPDK stack end-to-end orchestrator

server-app/
├── server.py           # Standard TCP server
├── README.md
└── tests/
    └── test_server.py  # Server unit tests

infra/
├── scapy/              # AWS CDK stack: Scapy data plane (Python on ClientNIC)
│   ├── deploy.ps1 / destroy.ps1
│   └── cdk/
│       ├── packet_test_stack.py   # VPC with Client/Middle/Server subnets
│       └── smartnics_stack.py     # EC2 instances, ENIs, route tables
├── dpdk/               # AWS CDK stack: DPDK data plane (C/DPDK on ClientNIC)
│   ├── deploy.ps1 / destroy.ps1
│   └── cdk/
│       ├── packet_test_stack.py   # VPC (same topology)
│       └── smartnics_stack.py     # ClientNIC gets DPDK 23.11 + vfio-pci + binary build
└── bluefield/          # NVIDIA BlueField-3 DPU infrastructure and examples
    ├── docs/           # Architecture, programming, operations, development guides
    ├── examples/       # syn-punt, react, wire-example DOCA/DPDK implementations
    ├── deployment/     # Docker and BFB image setup
    └── setup/          # DPU mode configuration and scripts

openspec/
├── changes/            # Experimental spec-driven change tracking
│   ├── t8-isn-ack-num-translation-shift/    # Active: ISN passing for ServerNIC
│   ├── aws-to-onprem-full-dpdk-migration/   # Migration planning to Bluefield
│   ├── phase-1a-ebpf-observability/         # Phase-1 initiative
│   ├── phase-1b-iperf3-stress-testing/      # Phase-1 initiative
│   └── archive/        # Completed changes (DPDK port, SSM tests, node integration)

todos/
├── urgents.md          # Critical items (RUNS lab, ServerNIC stability)
└── tech-improvements.md  # Architecture work (T8 ISN-passing, sequence translation)

venv/                   # Shared Python venv for local dev (all components)
```

### Deploying Infrastructure

**AWS EC2 Deployments:**
```powershell
cd infra/dpdk         # or infra/scapy
.\deploy.ps1          # Creates/activates repo-root venv, installs deps, deploys
.\deploy.ps1 -Bootstrap  # First-time CDK bootstrap + deploy
.\destroy.ps1         # Tear down all stacks
```
Note: the DPDK stack's ClientNIC user data builds DPDK 23.11 from source (~15-20 min after deploy before the binary is ready).

**BlueField-3 DPU Setup:**
- Refer to `infra/bluefield/docs/` for architecture, DOCA Flow programming, and DPA cores
- Check `infra/bluefield/setup/` for OS image installation and driver setup
- Review example implementations in `infra/bluefield/examples/` (syn-punt, react patterns)
- Use `infra/bluefield/deployment/` for Docker-based DPU application deployment
