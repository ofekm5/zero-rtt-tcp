## ADDED Requirements

### Requirement: Forwarded SYN ingestion
When a forwarded SYN arrives from the ClientNIC, the ServerNIC SHALL extract the flow key, read `V` from the ack-num field, create or update a PENDING flow entry storing `V`, zero the ack-num field, recompute the TCP checksum, and forward the SYN to the Server.

#### Scenario: First forwarded SYN for a new flow
- **WHEN** a SYN with ack-num=`V` arrives on the ClientNIC-facing interface for a 4-tuple not in the flow table
- **THEN** a PENDING flow entry SHALL be created with spoofed_server_isn=`V`, the ack-num SHALL be set to 0, the TCP checksum recomputed, and the SYN forwarded to the Server

#### Scenario: Retransmitted forwarded SYN
- **WHEN** a SYN with ack-num=`V` arrives for a 4-tuple already PENDING
- **THEN** the existing entry SHALL be retained (no duplicate creation), the ack-num zeroed, checksum recomputed, and the SYN forwarded to the Server

### Requirement: Real SYN-ACK processing
When the real SYN-ACK arrives from the Server, the ServerNIC SHALL compute the seq delta, transition the flow to ACTIVE, flush buffered client→server packets (rewriting their ACK numbers), and DROP the real SYN-ACK so the client never receives a second SYN-ACK.

#### Scenario: Real SYN-ACK for a pending flow
- **WHEN** a SYN-ACK with seq=`real_isn` arrives on the Server-facing interface for a PENDING flow with spoofed_server_isn=`V`
- **THEN** delta SHALL be set to `(V − real_isn) & 0xFFFFFFFF`, the flow marked ACTIVE, buffered packets flushed with ACK rewritten and checksums recomputed, and the real SYN-ACK SHALL be dropped (not forwarded toward the ClientNIC)

#### Scenario: Real SYN-ACK for unknown flow
- **WHEN** a SYN-ACK arrives on the Server-facing interface for a flow key not in the table
- **THEN** the packet SHALL be dropped with a warning log

### Requirement: Buffered packet flush addressing
When flushing buffered client→server packets after delta computation, each packet's ACK SHALL be rewritten by subtracting the delta with 32-bit wraparound, IP and TCP checksums recomputed, and the packet sent toward the Server.

#### Scenario: Flush rewrites and forwards
- **WHEN** a flow transitions to ACTIVE with `N` buffered client→server packets
- **THEN** each of the `N` packets SHALL have its ACK set to `(ack − delta) & 0xFFFFFFFF`, checksums recomputed, and be sent on the Server-facing interface
