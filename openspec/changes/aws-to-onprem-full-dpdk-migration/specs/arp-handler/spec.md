## ADDED Requirements

### Requirement: Pipeline responds to ARP requests on both interfaces
The system SHALL inspect the ethertype of every received frame before TCP dispatch. If ethertype is ARP (0x0806) and the ARP operation is REQUEST targeting the local interface's IP, the system SHALL construct and transmit an ARP REPLY in-place on the same interface.

#### Scenario: ARP request for eth0 IP received on eth0
- **WHEN** an ARP WHO-HAS request arrives on eth0 targeting eth0's assigned IP
- **THEN** the pipeline sends an ARP REPLY with eth0's MAC and continues (frame is not forwarded)

#### Scenario: ARP request for eth1 IP received on eth1
- **WHEN** an ARP WHO-HAS request arrives on eth1 targeting eth1's assigned IP
- **THEN** the pipeline sends an ARP REPLY with eth1's MAC and continues

#### Scenario: ARP request for unknown IP received
- **WHEN** an ARP request arrives targeting an IP not assigned to either interface
- **THEN** the frame is silently dropped (no reply sent)

### Requirement: Non-ARP, non-TCP frames are silently dropped
The system SHALL drop any frame that is neither IPv4/TCP nor ARP without logging at INFO level (to avoid log spam from broadcast/multicast traffic).

#### Scenario: LLDP or other L2 broadcast received
- **WHEN** a frame with ethertype other than 0x0800 (IPv4) or 0x0806 (ARP) is received
- **THEN** the frame is dropped silently

### Requirement: Gratuitous ARP sent on both interfaces at startup
The system SHALL send a gratuitous ARP announcement (ARP REQUEST with sender IP = target IP = own IP) on both eth0 and eth1 immediately after port initialization to warm neighbor caches.

#### Scenario: Startup gratuitous ARP
- **WHEN** both DPDK ports have been started and configured
- **THEN** one gratuitous ARP frame is transmitted on each interface before entering the main poll loop
