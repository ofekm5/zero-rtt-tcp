## ADDED Requirements

### Requirement: Client-to-server transparent forwarding
For non-SYN packets from eth0, the `dpdk-forwarder` variant SHALL forward the packet on eth1 without modifying the TCP seq or ack fields, rewriting only the Ethernet header (src=eth1 MAC, dst=gateway MAC). Seq/ack translation is performed downstream by the ServerNIC.

#### Scenario: Forward client data unchanged
- **WHEN** a non-SYN packet arrives on eth0 for a known flow
- **THEN** the TCP seq and ack fields SHALL be unchanged, the Ethernet header rewritten for eth1, and the packet sent on eth1

#### Scenario: Unknown flow on eth0
- **WHEN** a non-SYN packet arrives on eth0 for a flow key not in the table
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Server-to-client transparent forwarding
For packets from eth1, the `dpdk-forwarder` variant SHALL forward the packet on eth0 without modifying the TCP seq or ack fields, rewriting only the Ethernet header (src=eth0 MAC, dst=client MAC from the flow entry). The seq has already been translated by the ServerNIC.

#### Scenario: Forward server data to client unchanged
- **WHEN** a packet arrives on eth1 for a known flow
- **THEN** the TCP seq and ack fields SHALL be unchanged, the Ethernet header rewritten with the cached client MAC as destination, and the packet sent on eth0

#### Scenario: No checksum recomputation on the data path
- **WHEN** a data packet is forwarded in either direction without seq/ack modification
- **THEN** the existing IP and TCP checksums SHALL remain valid and SHALL NOT require recomputation
