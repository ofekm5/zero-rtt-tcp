## ADDED Requirements

### Requirement: Orchestrator discovers and passes endpoint peer MACs
Because the endpoint-facing SmartNIC ports are DPDK (no ARP), the orchestrator SHALL discover the Client's and Server's data-ENI MAC addresses (via EC2 `describe-instances` or `/sys/class/net/*/address` over SSM) and pass them to the SmartNIC node scripts as `--client-mac` (to ClientNIC) and `--server-mac` (to ServerNIC).

#### Scenario: Peer MACs discovered and passed
- **WHEN** the orchestrator launches the SmartNIC node scripts
- **THEN** it SHALL pass the Client data-ENI MAC to `clientnic.sh` and the Server data-ENI MAC to `servernic.sh`

#### Scenario: Peer MAC discovery fails
- **WHEN** a required peer MAC resolves empty or "None"
- **THEN** the orchestrator SHALL exit with a clear error before launching the affected SmartNIC

### Requirement: No SmartNIC-side packet capture on DPDK-owned interfaces
The node scripts SHALL NOT run `tcpdump` on a SmartNIC's endpoint-facing interface once it is DPDK-bound (the kernel cannot see a vfio-pci NIC). Metrics SHALL be sourced from the Client and Server host captures per the `endpoint-pcap-measurement` model.

#### Scenario: No tcpdump on the converted interface
- **WHEN** `clientnic.sh` runs with the client-facing interface bound to DPDK
- **THEN** it SHALL NOT start a `tcpdump` on that interface, and analysis SHALL use the Client host's `/tmp/client_side.pcap`
