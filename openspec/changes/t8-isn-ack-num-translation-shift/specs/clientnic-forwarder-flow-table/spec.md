## ADDED Requirements

### Requirement: Flow key identification
A flow SHALL be identified by a 4-tuple: (src_ip, src_port, dst_ip, dst_port) stored in network byte order in a `struct flow_key`.

#### Scenario: Extract key from packet headers
- **WHEN** a TCP/IP packet is parsed
- **THEN** a `flow_key` SHALL be extracted from the IP source/destination and TCP source/destination port fields

#### Scenario: Reverse key for server-to-client direction
- **WHEN** a packet arrives from the server (eth1)
- **THEN** a reverse `flow_key` SHALL be constructed by swapping src↔dst for both IP and port fields

### Requirement: Slim flow entry state tracking
Each `dpdk-forwarder` flow entry SHALL store only: `spoofed_server_isn` (`V`, host order), `state` (SYN_SENT or ESTABLISHED), and `client_mac` (6 bytes). The entry SHALL NOT contain `seq_delta`, `delta_valid`, or a packet buffer — those belong to the ServerNIC under T8.

#### Scenario: New flow creation
- **WHEN** a SYN is intercepted
- **THEN** a flow entry SHALL be created with state=SYN_SENT, spoofed_server_isn set to the chosen `V`, and client_mac copied from the SYN's source Ethernet address

#### Scenario: Lookup for retransmit re-stamping
- **WHEN** a SYN is forwarded again for an existing flow
- **THEN** the entry SHALL provide the stored `V` so the forwarded SYN's ack-num can be re-stamped with the same value

#### Scenario: Lookup for server-to-client addressing
- **WHEN** a packet arrives on eth1 for a known flow
- **THEN** the entry SHALL provide the cached `client_mac` used as the Ethernet destination when forwarding to eth0

### Requirement: Fixed-size hash table
The flow table SHALL use a fixed-size open-addressing hash table (1024 slots) with linear probing, keyed by `flow_key`.

#### Scenario: Flow lookup
- **WHEN** `ft_lookup()` is called with a flow key
- **THEN** it SHALL return a pointer to the matching flow entry, or NULL if not found

#### Scenario: Hash collision
- **WHEN** two different flow keys hash to the same slot
- **THEN** linear probing SHALL find the next available slot for insertion and correctly locate both entries on lookup
