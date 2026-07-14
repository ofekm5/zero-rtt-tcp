## ADDED Requirements

### Requirement: Orchestrator discovers and passes next-hop and port-identity MACs
Because the endpoint-facing SmartNIC ports are DPDK (no ARP, and no kernel netdev to read), the orchestrator SHALL discover — via EC2 `describe-instances` (or `/sys/class/net/*/address` over SSM on the RUNS lab) — and pass to the SmartNIC node scripts:

- **Next-hop (peer) MACs**, used as TX destinations: the ServerNIC's Middle-subnet ENI MAC (to ClientNIC as `--gw-mac`), the ClientNIC's Middle-subnet ENI MAC (to ServerNIC as `--gw-mac`), and the Server's ENI MAC (to ServerNIC as `--server-mac`).
- **Port-identity MACs**, used to resolve which DPDK port plays which role: each SmartNIC's own two data-ENI MACs (as `--client-port-mac` / `--server-port-mac`).

The Client's MAC SHALL NOT be discovered or passed: the ClientNIC learns it per-flow from the SYN.

#### Scenario: MACs discovered and passed
- **WHEN** the orchestrator launches the SmartNIC node scripts
- **THEN** each SmartNIC SHALL receive both its next-hop MACs and its own two DPDK port MACs

#### Scenario: MAC discovery fails
- **WHEN** any required MAC resolves empty or "None"
- **THEN** the orchestrator SHALL exit with a clear error naming the variable, before launching the affected SmartNIC

#### Scenario: No kernel-name-based DPDK rebinding at startup
- **WHEN** a SmartNIC node script starts
- **THEN** it SHALL NOT attempt to detect or "fix" which kernel interface is DPDK-bound — port roles are resolved by the binary from the port-identity MACs, and a name-based rebind under dual-DPDK would unbind an arbitrary vfio device

### Requirement: No SmartNIC-side packet capture on DPDK-owned interfaces
The node scripts SHALL NOT run `tcpdump` on a SmartNIC's endpoint-facing interface once it is DPDK-bound (the kernel cannot see a vfio-pci NIC). Metrics SHALL be sourced from the Client and Server host captures per the `endpoint-pcap-measurement` model.

#### Scenario: No tcpdump on the converted interface
- **WHEN** `clientnic.sh` runs with the client-facing interface bound to DPDK
- **THEN** it SHALL NOT start a `tcpdump` on that interface, and analysis SHALL use the Client host's `/tmp/client_side.pcap`
