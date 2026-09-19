---
type: Index
title: "zero-rtt-tcp Wiki Index"
description: "Master table of contents for the zero-rtt-tcp llm-wiki vault."
tags: [index]
timestamp: 2026-08-08T00:00:00+03:00
---

# zero-rtt-tcp Wiki Index

This vault is an LLM-readable knowledge base layered on top of the
[zero-rtt-tcp](https://github.com) repo's documentation. Four folders, one
contract:

- **`wiki/`** — distilled, cross-linked notes. One per component/concept. Start here.
- **`raw/`** — verbatim, append-only archive of dated experiment reports (`raw/YYYY-MM-DD-<slug>.md`). Never edited; superseded reports stay, they aren't deleted.
- **`index/`** — this file. Regenerated whenever notes are added, moved, or renamed.
- **`log/`** — `log/log.md`, an append-only record of every mutation made to this vault.

**Source of truth stays in the repo.** Notes under `wiki/` that came from a
living doc (a component README, an architecture doc) are *copies*, not moves —
each carries a `Source: \`path/in/repo\`` line under its frontmatter. If a
wiki note and its repo source diverge, the repo wins; re-run the llm-wiki
skill's INGEST mode to re-sync. The one exception is `wiki/Capacity Model.md`,
which was already relocated out of `docs/` before this refactor — `docs/` is
now empty.

## Project Overview

- [[wiki/Zero-RTT TCP Overview]] — what 0-RTT TCP is and why the ClientNIC/ServerNIC pair exists.
- [[wiki/Roadmap]] — open work ranked easiest win first; completed work lives in `docs/openspec/changes/archive/`.
- [[wiki/Known Limitations]] — acknowledged out-of-scope limits (scale beyond 2000 flows, spoofing amplifier); read before re-opening either.
- [[wiki/Capacity Model]] — hardware sizing ceilings (mbuf pool, NIC rings, flow tables, CPU) for the DPDK data plane.

## Experiments & Measurement

- [[wiki/Measurement Methodology]] — how load/latency are measured and whether that methodology supports the 0-RTT claim; §E covers the emulated WAN and proves only the ClientNIC↔ServerNIC leg can show an FCT win. Read before touching `NETEM_RTT_MS` or a `tc` command.
- [[wiki/Load Generation and Think Time]] — why `loadgen.py` beats iperf2 for this topology, what iperf2 is still for, and why a client think-time sweep must follow the netem fix rather than replace it.
- [[wiki/Experiment Insights]] — running log of confirmed root causes and durable findings from experiment runs.
- `raw/` — dated baseline and integration-test reports (19 files, 2026-03-06 through 2026-08-04) plus `2026-08-08-telemetry-review-artifact` (the published telemetry review). Not indexed individually here; browse by date or `search`.

## Components (Client → ClientNIC → ServerNIC → Server)

- [[wiki/components/Client App]] — unmodified TCP client, driven by `loadgen.py`.
- [[wiki/components/ClientNIC]] — core 0-RTT logic: intercepts SYN, spoofs SYN-ACK, forwards toward the server.
- [[wiki/components/ClientNIC DPDK Forwarder]] — live: spoof + stamp V + transparent forward.
- [[wiki/components/ClientNIC DPDK Forwarder Tests]] — virtual-PMD smoke tests for the forwarder binary.
- [[wiki/components/ServerNIC]] — sole stateful translator in the live DPDK implementation; reads V, computes delta, rewrites packets.
- [[wiki/components/ServerNIC DPDK]] — DPDK implementation of the ServerNIC translator.
- [[wiki/components/Server App]] — unmodified TCP server, driven by `loadgen.py`.

## AWS Infra

- [[wiki/infra/DPDK Stack Architecture]] — VPC/instance topology for the live DPDK data-plane CDK stack.
- [[wiki/infra/Scapy Stack Architecture (Deprecated)]] — topology for the deprecated Scapy feasibility stack.

## Hermes Agents

- [[wiki/hermes/Hermes Agents Overview]] — the three Hermes agents that run/read AWS experiments from a phone.

## BlueField-3 DPU

- [[wiki/bluefield/BlueField Docs Overview]] — start here for DPU docs; covers architecture, programming, operations, reference.

### Architecture
- [[wiki/bluefield/architecture/Hardware Overview]] — maps BlueField-3 hardware components and their relationships.
- [[wiki/bluefield/architecture/Eswitch Flow Engine]] — the eSwitch is not separate hardware; it's the NIC Flow Engine wearing a different hat.
- [[wiki/bluefield/architecture/Packet Pipeline]] — complete packet flow from ingress to egress.
- [[wiki/bluefield/architecture/Queues Ports SFs]] — queues, ports, and Scalable Functions explained.

### Programming
- [[wiki/bluefield/programming/DOCA Flow API]] — hardware flow programming via `rte_flow` and `doca_flow`.
- [[wiki/bluefield/programming/DOCA DPL P4]] — P4-based declarative pipeline programming.
- [[wiki/bluefield/programming/DOCA ARGP]] — argument-parsing library for DOCA apps.
- [[wiki/bluefield/programming/DOCA Logging]] — DOCA's logging backends, levels, and source control.
- [[wiki/bluefield/programming/DPA Programming]] — programming the DPA cores (verify function names against the installed SDK).
- [[wiki/bluefield/programming/DPDK Core Functions]] — EAL init, lcore management, application control.
- [[wiki/bluefield/programming/DPDK Integration]] — queue setup, packet loops, hardware feature integration.
- [[wiki/bluefield/programming/DPDK Utility Functions]] — error handling, memory, timing, port management helpers.
- [[wiki/bluefield/programming/Packet Modification]] — packet modification and generation APIs.

### Operations
- [[wiki/bluefield/operations/Hugepages Setup]] — configuring and verifying hugepage allocation.
- [[wiki/bluefield/operations/OVS Management]] — inspecting OVS topology, flows, and offload state.
- [[wiki/bluefield/operations/SF Management]] — creating and configuring Scalable Functions with `mlnx-sf`.

### Development
- [[wiki/bluefield/development/Local Simulation Strategies]] — developing/testing without physical BlueField hardware.
- [[wiki/bluefield/development/Testing Strategies]] — validating DPDK/DOCA apps on BlueField-3.
- [[wiki/bluefield/development/Debugging Guide]] — symptom-driven debugging (e.g. packets arriving but not reaching destination).
- [[wiki/bluefield/development/Performance Tuning]] — offload verification and performance optimization.
- [[wiki/bluefield/development/Code Examples]] — practical code examples (some superseded by the programming guides).

### Reference
- [[wiki/bluefield/reference/API Cheatsheet]] — quick-reference DOCA/DPDK API snippets.
- [[wiki/bluefield/reference/CLI Commands]] — quick-reference CLI commands (`mlnx-sf`, `ovs-vsctl`, DOCA tools).
- [[wiki/bluefield/reference/Gotchas]] — common misconceptions about BlueField-3 architecture and programming.

### Setup
- [[wiki/bluefield/setup/BFB Install]] — installing a BFB image onto a BlueField DPU host.
- [[wiki/bluefield/setup/DPU Mode Setup]] — configuring DPU mode from host or DPU CLI.

### Examples
- [[wiki/bluefield/examples/syn-punt/Syn-Punt README]] — production-quality DOCA app: hardware packet processing with selective exception handling.
- [[wiki/bluefield/examples/syn-punt/Syn-Punt Quickstart]] — quick start for the lab topology (Host VM → pf0hpf → BF3 → p0 → Tofino).
- [[wiki/bluefield/examples/syn-punt/Syn-Punt Topology]] — network wiring diagram for the SYN-punt lab.
- [[wiki/bluefield/examples/syn-punt/Syn-Punt Option1 Fixed]] — fix for the RSS forwarding bug on non-SYN packets in bump-in-the-wire mode.
- [[wiki/bluefield/examples/syn-punt/Syn-Punt Changes]] — changelog; notes the `docaflow.c`/`.h` naming collision with official DOCA headers.
- [[wiki/bluefield/examples/react/React Experiment]] — running/debugging notes for the ReACT DNS-filtering experiment.
- [[wiki/bluefield/examples/react/ReACT DOCA Analysis]] — analysis of the ReACT DOCA application (Dr. David Hay, Princeton).
- [[wiki/bluefield/examples/wire-example/Wire Example README]] — bidirectional wire from one port to another.
- [[wiki/bluefield/examples/wire-example/Wire Example Networking Setup]] — Classic DPDK Mode networking, with/without OVS/smartnic mode.
- [[wiki/bluefield/examples/wire-example/Wire Example Docker]] — containerizing and deploying wire-example with Docker + SFs.

## Explicitly out of scope for this vault

Kept in the repo, not mirrored here, because other tooling reads them by exact
path: `.claude/skills/**` (Claude Code's skill loader), `docs/openspec/**` (its own
spec-driven change-tracking system with dedicated propose/archive/sync
skills), `hermes/*/SOUL.md` (live agent configs), and `CLAUDE.md` (session-start
import).
