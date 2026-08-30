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

### Requirement: Hugepage allocation and data-plane port initialisation

The probe SHALL allocate hugepages on the DPU ARM and initialise `pf0hpf` as a data-plane port.

#### Scenario: Hugepages allocated and the port initialises

- **WHEN** the harness allocates hugepages on the ARM and starts the probe against `pf0hpf`
- **THEN** the probe's startup output reports `pf0hpf` initialised without error

#### Scenario: Probe toolchain is transported, not installed

- **WHEN** the probe program requires a build toolchain absent from the DPU ARM
- **THEN** it is built inside the DOCA devel container on a host with working DNS
- **AND** it reaches the DPU as a saved image tarball that is loaded locally

#### Scenario: No network-dependent package installation is attempted

- **WHEN** the harness runs any step on the DPU ARM
- **THEN** it SHALL NOT invoke `apt`, `pip`, a container registry pull, or any other step requiring DNS resolution from the DPU
- **AND** any toolchain the harness needs beyond preinstalled tooling arrives as an image built elsewhere and transported to the DPU

### Requirement: Composed e-switch rule

The probe SHALL install a single rule in the e-switch domain composing 5-tuple matching, TCP sequence-number modification by a per-flow constant, and egress back toward the host port, with a counter attached.

#### Scenario: Rule is accepted

- **WHEN** the harness creates a rule in the e-switch domain with a 5-tuple match, a TCP sequence-number modification using an ADD or SUB operation, an egress action toward the host port, and a counter
- **THEN** the rule-creation call returns a valid handle rather than an error

#### Scenario: Rule is rejected

- **WHEN** rule creation returns an error instead of a valid handle
- **THEN** the harness records the verbatim error text
- **AND** the run proceeds to the cross-check rather than concluding

#### Scenario: Rule parameters are supplied without rebuilding

- **WHEN** the operator varies the 5-tuple, the delta, or the egress target
- **THEN** the probe accepts them as command-line arguments
- **AND** no rebuild or re-transport of the probe image is required

#### Scenario: Installed build predates the required capability

- **WHEN** the recorded DOCA or DPDK version does not support TCP sequence-number modification
- **THEN** the harness reports a tooling limitation
- **AND** it SHALL NOT record the outcome as a hardware NO verdict

### Requirement: Hardware-execution verification

The probe SHALL distinguish a rule executed in hardware from a rule serviced by software on an ARM core.

#### Scenario: Rule executes in hardware

- **WHEN** traffic matching the rule is generated and the harness reads the rule's hardware counter and the probe's software-queue receive count
- **THEN** the rule's hit counter increments
- **AND** the probe reports zero packets received on an ARM software queue

#### Scenario: Rule falls back to software

- **WHEN** the rule's hit counter increments but the probe reports a nonzero software-queue receive count
- **THEN** the harness records that the rule was not offloaded
- **AND** the run SHALL NOT be recorded as a YES verdict

### Requirement: On-wire rewrite verification

The probe SHALL confirm the sequence-number rewrite by observing returned packets at the traffic source, not by inferring it from API return codes or counters.

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
- **THEN** the harness records a YES verdict with the captured evidence, the DOCA and DPDK versions, and the firmware version
- **AND** it records that the result was obtained through the API the companion change is most likely to ship

#### Scenario: PARTIAL verdict distinguishes the failing leg

- **WHEN** sequence-number rewrite is demonstrated but the return leg to the host port does not complete
- **THEN** the harness records a PARTIAL verdict naming the egress path as the failing sub-capability
- **AND** it records that a Scalable Function egress topology is the applicable fallback

#### Scenario: NO verdict requires the cross-check

- **WHEN** the sequence-number modification action is rejected or performs no rewrite under DOCA Flow
- **THEN** the harness SHALL NOT record a NO verdict until the `rte_flow` cross-check has run
- **AND** a NO verdict recorded after a negative cross-check states that no topology change rescues the offload architecture

### Requirement: Conditional rte_flow cross-check

Because DOCA Flow and `rte_flow` drive the same hardware steering but do not expose identical action sets, a negative DOCA Flow result SHALL be disambiguated by an `rte_flow` attempt before it is treated as a hardware limitation.

#### Scenario: Cross-check runs only on a negative result

- **WHEN** the DOCA Flow probe returns a positive result
- **THEN** the harness does not run the `rte_flow` cross-check

#### Scenario: Cross-check runs after a negative result

- **WHEN** the DOCA Flow probe fails to accept or fails to apply the sequence-number modification
- **THEN** the harness attempts the same TCP sequence-number modification through `rte_flow` using the preinstalled `dpdk-testpmd`
- **AND** the cross-check requires no build, image transport, or package installation

#### Scenario: Cross-check scope is limited to disambiguation

- **WHEN** the `rte_flow` cross-check runs
- **THEN** it attempts only the sequence-number modification
- **AND** it SHALL NOT perform hairpin egress, traffic generation, or on-wire capture

#### Scenario: Cross-check succeeds where DOCA Flow failed

- **WHEN** the `rte_flow` cross-check applies the modification that DOCA Flow could not
- **THEN** the harness records a PARTIAL verdict rather than a YES or a NO
- **AND** it records that the capability exists but is reachable only through `rte_flow` on this build

### Requirement: Restoration to pre-spike state

The probe SHALL return the DPU to the state recorded in the baseline, and SHALL treat successful restoration as part of the run's outcome rather than as optional cleanup.

#### Scenario: DPU restored and verified

- **WHEN** the probe run completes for any verdict
- **THEN** `pf0hpf` is re-attached to `ovsbr1`, hugepages are freed, any container image loaded for the probe is removed, and `ens16f0np0` is returned to its recorded state
- **AND** `ovs-vsctl show` matches the captured baseline

#### Scenario: Restoration is incomplete

- **WHEN** the post-run state does not match the baseline
- **THEN** the harness reports the differing values
- **AND** the run SHALL NOT be reported as successful regardless of the capability verdict

#### Scenario: Management access is never at risk

- **WHEN** the harness detaches `pf0hpf` or mutates any data-plane interface
- **THEN** it SHALL NOT modify `oob_net0`, over which DPU management access runs
