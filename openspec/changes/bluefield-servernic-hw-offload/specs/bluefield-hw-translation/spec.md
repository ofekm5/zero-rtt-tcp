## ADDED Requirements

### Requirement: Directional rule pair per flow

The hardware data path SHALL express each flow's translation as a pair of transfer-domain rules, one per direction, because the two directions modify different TCP header fields with different operations.

#### Scenario: Client-to-server direction

- **WHEN** the rule pair for a flow is composed
- **THEN** the client-to-server rule matches the flow's 5-tuple and subtracts the flow's delta from the TCP acknowledgment number

#### Scenario: Server-to-client direction

- **WHEN** the rule pair for a flow is composed
- **THEN** the server-to-client rule matches the reversed 5-tuple and adds the flow's delta to the TCP sequence number

#### Scenario: Both rules share one delta

- **WHEN** a flow's delta is computed
- **THEN** both rules of that flow's pair are composed from that same delta value

### Requirement: Hardware execution without a CPU in the path

Matched post-handshake packets SHALL be rewritten and returned by the e-switch without being received by software on the ARM cores.

#### Scenario: Matched packets are counted in hardware

- **WHEN** post-handshake packets matching a live rule traverse the DPU
- **THEN** the rule's hardware counter increments by the number of packets matched

#### Scenario: Matched packets bypass software entirely

- **WHEN** the rule's hardware counter increments for post-handshake packets
- **THEN** the control plane's non-handshake receipt counter remains at zero over the same interval

#### Scenario: Rewrite is applied on the wire

- **WHEN** a server-to-client data packet traverses a flow with live rules
- **THEN** the packet observed at the client carries a sequence number equal to the server's original sequence number plus the flow's delta

### Requirement: Single-port return path

Because the DPU's `p0` has no carrier and the card exposes no second physical port, the data path SHALL return rewritten packets over the same host-facing port on which they arrived.

#### Scenario: Rewritten packet returns over the ingress port

- **WHEN** a packet arrives on the host-facing port and matches a live rule
- **THEN** the rewritten packet is returned over that same host-facing port

#### Scenario: Egress target is a single point of change

- **WHEN** the return leg must instead target a Scalable Function representor
- **THEN** only the rule's egress action changes
- **AND** the rule's match criteria and modification actions are unaffected

### Requirement: Correct end-to-end translation

A TCP connection traversing the DPU SHALL transfer data correctly, with the client and server applications remaining unmodified and unaware of the translation.

#### Scenario: Connection completes with correct data

- **WHEN** a client opens a connection through the DPU and transfers data to the server
- **THEN** the transfer completes without error
- **AND** the data received matches the data sent

#### Scenario: Translation is consistent for the connection's lifetime

- **WHEN** a connection remains open across many packets in both directions
- **THEN** every packet is translated using the same delta established at handshake time
