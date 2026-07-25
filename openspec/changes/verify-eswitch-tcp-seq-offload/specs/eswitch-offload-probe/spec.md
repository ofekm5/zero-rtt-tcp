## ADDED Requirements

### Requirement: Pre-mutation baseline capture

The probe SHALL record the DPU's data-plane state before making any change, so that restoration can be objectively verified rather than assumed.

#### Scenario: Baseline recorded before first mutation

- **WHEN** the probe harness starts
- **THEN** it records `ovs-vsctl show` output, `pf0hpf` bridge membership, the ARM hugepage count, the DPDK version under `/opt/mellanox/dpdk`, and the adapter firmware version to a baseline file
- **AND** it makes no change to the DPU until the baseline file exists on disk

#### Scenario: Baseline capture fails

- **WHEN** any baseline value cannot be read
- **THEN** the harness aborts without mutating the DPU
- **AND** it reports which value could not be read

### Requirement: Hugepage allocation and DPDK port binding

The probe SHALL allocate hugepages on the DPU ARM and bind `pf0hpf` as a DPDK port, using only preinstalled tooling.

#### Scenario: Hugepages allocated and testpmd binds the port

- **WHEN** the harness allocates hugepages on the ARM and launches `dpdk-testpmd` against `pf0hpf`
- **THEN** `dpdk-testpmd` reaches the `testpmd>` prompt
- **AND** `show port summary all` lists `pf0hpf` as a bound port

#### Scenario: No package installation is attempted

- **WHEN** the harness runs any step on the DPU ARM
- **THEN** it invokes only tooling already present on the system
- **AND** it SHALL NOT invoke `apt`, `pip`, or any other network-dependent package installer

### Requirement: Composed transfer-domain rule

The probe SHALL install a single `rte_flow` rule in the transfer domain that composes 5-tuple matching, TCP sequence-number modification by a per-flow constant, and egress back toward the host port, with a counter attached.

#### Scenario: Rule is accepted by the PMD

- **WHEN** the harness issues `flow create` with `transfer`, a 5-tuple pattern, a `modify_field` action targeting `tcp_seq_num` with an ADD or SUB operation, an egress action toward the host port, and a `count` action
- **THEN** the mlx5 PMD returns a rule ID rather than an error

#### Scenario: Rule is rejected by the PMD

- **WHEN** `flow create` returns an error instead of a rule ID
- **THEN** the harness records the verbatim PMD error text
- **AND** the run concludes with a NO verdict

#### Scenario: DPDK build predates the required field

- **WHEN** the recorded DPDK version does not support `RTE_FLOW_FIELD_TCP_SEQ_NUM`
- **THEN** the harness reports a tooling limitation
- **AND** it SHALL NOT record the outcome as a hardware NO verdict

### Requirement: Hardware-execution verification

The probe SHALL distinguish a rule executed in hardware from a rule serviced by software on an ARM core.

#### Scenario: Rule executes in hardware

- **WHEN** traffic matching the rule is generated and the harness reads `flow query <id> count` and testpmd's forwarding statistics
- **THEN** the rule's hit counter increments
- **AND** testpmd's forwarding statistics show zero packets crossing an ARM core

#### Scenario: Rule falls back to software

- **WHEN** the rule's hit counter increments but testpmd's forwarding statistics show a nonzero packet count
- **THEN** the harness records that the rule was not offloaded
- **AND** the run SHALL NOT be recorded as a YES verdict

### Requirement: On-wire rewrite verification

The probe SHALL confirm the sequence-number rewrite by observing returned packets at the traffic source, not by inferring it from PMD return codes or counters.

#### Scenario: Rewrite observed at the sender

- **WHEN** the x86 host VM sends TCP packets with a known sequence number out `ens16f0np0` and captures on the same interface
- **THEN** the captured returned packets carry a sequence number equal to the sent sequence number plus or minus the configured delta

#### Scenario: Packets return unmodified

- **WHEN** returned packets carry the original, unmodified sequence number
- **THEN** the harness records that the rule matched but performed no rewrite
- **AND** the run concludes with a NO verdict

#### Scenario: No packets return

- **WHEN** no packets are captured at the sender within the capture window
- **THEN** the harness records that the return leg did not complete
- **AND** the run concludes with a PARTIAL verdict attributed to the egress path

### Requirement: Verdict recording

The probe SHALL produce a written verdict of YES, NO, or PARTIAL, distinguishing which sub-capability failed, together with the evidence and the environment it was obtained on.

#### Scenario: YES verdict

- **WHEN** the rule is accepted, its counter increments with zero software forwarding, and returned packets carry the modified sequence number
- **THEN** the harness records a YES verdict with the captured evidence, the DPDK version, and the firmware version
- **AND** it records that the result is indicative pending DOCA Flow confirmation

#### Scenario: PARTIAL verdict distinguishes the failing leg

- **WHEN** sequence-number rewrite is demonstrated but the return leg to the host port does not complete
- **THEN** the harness records a PARTIAL verdict naming the egress path as the failing sub-capability
- **AND** it records that a Scalable Function egress topology is the applicable fallback

#### Scenario: NO verdict is unconditional

- **WHEN** the sequence-number modification action is rejected or performs no rewrite
- **THEN** the harness records a NO verdict
- **AND** it records that no topology change rescues the offload architecture

### Requirement: Restoration to pre-spike state

The probe SHALL return the DPU to the state recorded in the baseline, and SHALL treat successful restoration as part of the run's outcome rather than as optional cleanup.

#### Scenario: DPU restored and verified

- **WHEN** the probe run completes for any verdict
- **THEN** `pf0hpf` is re-attached to `ovsbr1`, hugepages are freed, and `ens16f0np0` is returned to its recorded state
- **AND** `ovs-vsctl show` matches the captured baseline

#### Scenario: Restoration is incomplete

- **WHEN** the post-run state does not match the baseline
- **THEN** the harness reports the differing values
- **AND** the run SHALL NOT be reported as successful regardless of the capability verdict

#### Scenario: Management access is never at risk

- **WHEN** the harness detaches `pf0hpf` or mutates any data-plane interface
- **THEN** it SHALL NOT modify `oob_net0`, over which DPU management access runs
