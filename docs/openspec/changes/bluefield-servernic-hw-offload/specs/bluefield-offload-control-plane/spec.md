## ADDED Requirements

### Requirement: Handshake-only packet dispatch

The DPU control plane SHALL receive and process only TCP handshake and teardown packets — SYN, SYN-ACK, FIN, and RST. All other packets SHALL be handled by the hardware data path without reaching software.

#### Scenario: Handshake packets reach software

- **WHEN** a SYN, SYN-ACK, FIN, or RST packet for a tracked flow arrives at the DPU
- **THEN** the control plane receives it and dispatches it to the corresponding handler

#### Scenario: Data packets do not reach software

- **WHEN** a post-handshake data packet arrives for a flow whose hardware rules are live
- **THEN** the control plane's counter of received non-handshake packets does not increment

#### Scenario: Non-handshake receipt is counted, not silently discarded

- **WHEN** the control plane receives a packet that is not SYN, SYN-ACK, FIN, or RST
- **THEN** it increments a dedicated counter for non-handshake receipts
- **AND** that counter is externally readable, so the hardware-only claim is measurable rather than assumed

### Requirement: V extraction and delta computation

The control plane SHALL recover the ClientNIC-stamped value V from the SYN's acknowledgment number and compute the per-flow sequence delta when the real SYN-ACK arrives, using 32-bit wraparound arithmetic.

#### Scenario: V recovered from the SYN

- **WHEN** a SYN arrives carrying a nonzero acknowledgment number
- **THEN** the control plane records V from that field for the flow
- **AND** it zeroes the acknowledgment number before forwarding the SYN toward the server

#### Scenario: Delta computed on the real SYN-ACK

- **WHEN** the real SYN-ACK arrives for a flow with a recorded V
- **THEN** the control plane computes the flow's delta from V and the server's real ISN using 32-bit wraparound arithmetic
- **AND** it drops the real SYN-ACK rather than forwarding it, because ClientNIC already sent a spoofed one

#### Scenario: SYN-ACK arrives for an unknown flow

- **WHEN** a SYN-ACK arrives for a flow with no recorded V
- **THEN** the control plane does not install any hardware rule for that flow

### Requirement: Pre-delta packet buffering and flush

The control plane SHALL buffer packets that arrive before a flow's delta is known, and SHALL rewrite and release them in software once the delta is computed.

#### Scenario: Packets buffered before the delta exists

- **WHEN** a packet arrives for a flow whose SYN has been seen but whose delta is not yet computed
- **THEN** the control plane buffers it rather than forwarding it untranslated

#### Scenario: Buffer flushed at delta computation

- **WHEN** the flow's delta is computed
- **THEN** the control plane rewrites each buffered packet in software using that delta and releases it
- **AND** the buffer for that flow is emptied

### Requirement: Per-flow hardware rule lifecycle

The control plane SHALL install a flow's hardware rules once its delta is known, and SHALL remove them when the connection is torn down, so that the installed rule count tracks live connections.

#### Scenario: Rules installed after delta computation

- **WHEN** a flow's delta becomes known
- **THEN** the control plane installs the flow's hardware rule set
- **AND** it installs exactly one rule set per flow, not one per packet

#### Scenario: Rules removed on teardown

- **WHEN** a FIN or RST is received for a flow with live hardware rules
- **THEN** the control plane removes that flow's hardware rules
- **AND** it releases the flow's table entry

#### Scenario: Rule count returns to baseline across repeated connections

- **WHEN** N connections are opened and closed in sequence
- **THEN** the installed hardware rule count returns to its pre-run value

#### Scenario: Rule installation fails

- **WHEN** hardware rule installation returns an error for a flow
- **THEN** the control plane records the failure
- **AND** it SHALL NOT report the flow as offloaded
