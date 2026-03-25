## ADDED Requirements

### Requirement: Single-NIC mode maps client and server directions to separate VLAN-tagged queue pairs
When launched with `--single-nic`, the system SHALL map eth0 (client-facing) to DPDK port 0 queue 0 with VLAN ID `--client-vlan <id>`, and eth1 (server-facing) to DPDK port 0 queue 1 with VLAN ID `--server-vlan <id>`. DPDK VLAN filtering SHALL be enabled so each queue receives only its designated VLAN traffic.

#### Scenario: Single-NIC mode enabled with valid VLANs
- **WHEN** `--single-nic --client-vlan 10 --server-vlan 20` is passed at launch
- **THEN** port 0 is configured with two RX/TX queue pairs, VLAN 10 filtered to queue 0 and VLAN 20 filtered to queue 1

#### Scenario: Single-NIC mode with duplicate VLAN IDs
- **WHEN** `--client-vlan` and `--server-vlan` are set to the same value
- **THEN** startup aborts with error: "client-vlan and server-vlan must be different"

### Requirement: VLAN IDs logged at startup in single-NIC mode
The system SHALL log the configured VLAN IDs and queue assignments at INFO level during initialization to aid in diagnosing switch misconfiguration.

#### Scenario: Startup log in single-NIC mode
- **WHEN** single-NIC mode is active
- **THEN** startup log includes: "Single-NIC mode: port=0 client-queue=0 vlan=<id> server-queue=1 vlan=<id>"

### Requirement: Two-NIC mode remains the default
When `--single-nic` is not passed, the system SHALL default to two-port mode (eth0 = port 0, eth1 = port 1) with no VLAN filtering. Single-NIC mode is opt-in only.

#### Scenario: No single-NIC flag, two ports available
- **WHEN** `--single-nic` is not passed and two DPDK ports are available
- **THEN** system initializes in standard two-port mode without VLAN configuration

#### Scenario: No single-NIC flag, only one port available
- **WHEN** `--single-nic` is not passed and only one DPDK port is available
- **THEN** startup aborts with error indicating two ports are required
