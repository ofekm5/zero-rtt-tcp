## ADDED Requirements

### Requirement: Spoofed ISN carried in forwarded SYN ack-num
The ClientNIC SHALL carry the spoofed server ISN `V` to the ServerNIC by writing `V` into the ack-num field (bytes 8–11) of the SYN it forwards toward the Server. The SYN's seq field (carrying the client ISN) and the SYN flag SHALL remain unchanged. After the rewrite the TCP checksum SHALL be recomputed.

#### Scenario: V written into forwarded SYN
- **WHEN** the ClientNIC forwards a client SYN with seq=`C_isn` for a flow whose chosen spoofed ISN is `V`
- **THEN** the forwarded SYN SHALL have ack-num == `V`, seq == `C_isn` unchanged, ACK flag clear, SYN flag set, and a valid recomputed TCP checksum

#### Scenario: Server never sees V
- **WHEN** the ServerNIC has read `V` from a forwarded SYN
- **THEN** the ServerNIC SHALL set the ack-num field to 0 and recompute the TCP checksum before forwarding the SYN to the Server, so the Server receives a SYN with ack-num == 0

### Requirement: V re-stamped on every forwarded SYN
Because the kernel may retransmit a SYN with ack-num == 0, the ClientNIC SHALL re-stamp the same `V` on every forwarded SYN for a given flow, not only the first.

#### Scenario: Retransmitted SYN carries the same V
- **WHEN** a SYN is forwarded again for a flow that already exists in the ClientNIC flow table with spoofed ISN `V`
- **THEN** the re-forwarded SYN SHALL carry ack-num == `V` (the original value for that flow), not 0

### Requirement: ServerNIC reads V at SYN time
The ServerNIC SHALL read `V` from the ack-num field of each forwarded SYN it receives on its ClientNIC-facing interface and record it against the flow's 4-tuple before forwarding the SYN to the Server.

#### Scenario: V recorded as pending flow state
- **WHEN** the ServerNIC receives a forwarded SYN with ack-num == `V` for a new 4-tuple
- **THEN** it SHALL create a flow entry storing `V` as the spoofed server ISN with state PENDING

### Requirement: Ak-num channel probe verification gate
Before the T8 channel is relied upon in a deployment, an operator-runnable probe SHALL confirm the ack-num field survives unchanged across the AWS VPC path between ClientNIC egress and ServerNIC ingress.

#### Scenario: Probe confirms field survives
- **WHEN** a SYN is emitted from the ClientNIC toward the Server with ack-num == `0xDEADBEEF` and the ServerNIC ingress is captured
- **THEN** the captured SYN's bytes 8–11 SHALL equal `0xDEADBEEF`, confirming no middlebox normalized the field

#### Scenario: Probe failure forces fallback
- **WHEN** the captured SYN's ack-num field at ServerNIC ingress differs from the emitted value
- **THEN** the T8 channel SHALL NOT be relied upon and the deployment SHALL fall back to a TCP-option carrier (T3)
