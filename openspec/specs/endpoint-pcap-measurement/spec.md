# endpoint-pcap-measurement Specification

## Purpose
TBD - created by archiving change endpoint-pcap-measurement. Update Purpose after archive.
## Requirements
### Requirement: Three endpoint-observed metrics

The system SHALL produce three metrics, each observed at an endpoint on that endpoint's own clock, derived from on-wire packet captures: (a) Flow Completion Time (FCT) = first SYN out → last data byte/FIN, on the Client; (b) send-unlock = first SYN out → first outbound segment with payload > 0, on the Client; (c) server-gap = first SYN-ACK out → first inbound data segment, on the Server. Each metric SHALL be a single-host interval whose two bracket events are both observed at one tap point on one host, so that no cross-machine clock synchronization is required.

#### Scenario: All three metrics derived from two captures

- **WHEN** `analyze_metrics.py` is run on a known-good `client_side.pcap` and `server_side.pcap`
- **THEN** it prints exactly three metrics — `fct` and `send_unlock` (node=client) and `server_gap` (node=server) — each as a value in milliseconds

#### Scenario: FCT and send-unlock share one source of truth

- **WHEN** the analyzer computes FCT and send-unlock
- **THEN** both SHALL be derived from the same `client_side.pcap` flow, keyed by the same 4-tuple anchored on the SYN to `server:<port>`

### Requirement: Portable across both infrastructures

The mechanism SHALL produce all three metrics from the same captures and the same analyzer on both target infrastructures: AWS EC2/DPDK (`Client → ClientNIC → ServerNIC → Server`, 2 middleboxes) and the University Proxmox LAN (`Client → middlebox/DPU → Server`, 1 middlebox). The number of middleboxes between the two tap points SHALL NOT affect any metric.

#### Scenario: Same analyzer on both infras

- **WHEN** captures are taken on AWS and on Proxmox for equivalent flows
- **THEN** the identical `analyze_metrics.py` invocation SHALL extract the three metrics from each without infra-specific code paths

#### Scenario: Shared runner core, two transports

- **WHEN** the AWS runner and the Proxmox runner execute an experiment
- **THEN** both SHALL source one shared core for "start captures → run iperf2 → stop → copy pcaps → analyze", differing only in node discovery and exec transport (AWS SSM vs Proxmox SSH-gateway)

### Requirement: Load generator stays unmodified

iperf2 SHALL remain completely unmodified and SHALL be the load generator on both infras. Coupling between the generator and the measurement SHALL be by capture window plus on-wire flow key only, never by patching, wrapping, or instrumenting iperf2.

#### Scenario: No generator patching

- **WHEN** the measurement runs
- **THEN** the analyzer SHALL identify the flow purely from packet captures (4-tuple, SYN anchor), requiring no machine-readable timing output from iperf2

#### Scenario: Optional defensive cross-check

- **WHEN** `iperf -y C` CSV output is logged alongside the flow
- **THEN** the system SHALL warn if pcap-derived FCT diverges from iperf2's reported duration by more than 10 ms, while pcap remains the source of truth

### Requirement: Capture on endpoint interfaces with high-precision timestamps

On each endpoint, `tcpdump` SHALL capture on the host's own data interface carrying the iperf2 flow, writing `client_side.pcap` on the Client and `server_side.pcap` on the Server. The capture window SHALL start before the client connects and stop after the flow completes, so that the SYN and the last data byte both fall inside it. Capture SHALL be filtered to the flow's TCP traffic without excluding the SYN/SYN-ACK/FIN, and SHALL request nanosecond high-precision timestamps (`--time-stamp-precision=nano -j host_hiprec`) with graceful fallback when a flag is unsupported.

#### Scenario: SYN and last byte inside the window

- **WHEN** tcpdump is started before connect and stopped after completion
- **THEN** the resulting pcap SHALL contain the flow's SYN and its last data segment/FIN

#### Scenario: Graceful timestamp fallback

- **WHEN** a kernel does not support `--time-stamp-precision=nano` or `-j host_hiprec`
- **THEN** tcpdump SHALL fall back to a supported timestamp mode rather than failing the capture

### Requirement: Accuracy knobs before capture

Before capture, the system SHALL disable hardware offload on both endpoints' capture interfaces (`ethtool -K <if> gro off lro off tso off gso off`) so that the first payload-bearing segment is a real on-wire segment and not a coalesced TSO/GRO frame. The system SHALL inject latency with `tc netem delay 50ms` on each endpoint (≈100 ms RTT) so the ~1-RTT 0-RTT saving is legible above the capture noise floor.

#### Scenario: Offload disabled corrupts no segment boundary

- **WHEN** offload is disabled and a flow is captured
- **THEN** the first outbound segment with payload > 0 SHALL reflect a real on-wire segment boundary

#### Scenario: Injected latency makes the saving legible

- **WHEN** `tc netem delay 50ms` is applied on each endpoint and a 0-RTT flow is captured
- **THEN** the analyzer SHALL report a send-unlock value an order of magnitude below the ~100 ms RTT

### Requirement: Machine-parseable analyzer output consumed by measure.sh

`analyze_metrics.py` SHALL emit each metric as a greppable key=value line of the form `metric=<name> value_ms=<v> node=<n> flow=<key>`. `experiments/utils/measure.sh` SHALL parse these lines and report the three metrics, and SHALL NOT rely on the dead `[METRIC] … node=… ttfb|fct` grep, which no component emits.

#### Scenario: measure.sh reports real metrics

- **WHEN** an experiment run completes and the analyzer output is passed to `measure.sh`
- **THEN** the report SHALL show non-empty `fct`, `send_unlock`, and `server_gap` values and SHALL NOT print "no samples found"

### Requirement: Validation guardrails reject incomplete captures

The analyzer SHALL flag or reject a flow where a required event is missing (no SYN, no payload-bearing segment, truncated capture) rather than emitting a wrong number. A silent absence of samples SHALL be treated as a failure, not a zero result.

#### Scenario: Truncated capture is flagged

- **WHEN** `analyze_metrics.py` is run on a pcap missing a required event
- **THEN** it SHALL exit non-zero and/or print a flag line identifying the missing event, rather than emitting a metric value

### Requirement: NIC diagnostics relabeled away from the metric channel

The DPDK middlebox `rdtsc` instrumentation SHALL be retained as middlebox-internal diagnostics but SHALL be relabeled from the `[METRIC]` log tag to `[DIAG]` in `clientnic/dpdk-forwarder/forwarder.c` and `servernic/dpdk/translator.c`, so it no longer masquerades as the experiment metric and is not parsed as a measurement source. The data-plane behavior SHALL be otherwise unchanged.

#### Scenario: Middlebox timing no longer parsed as a metric

- **WHEN** the DPDK data planes emit their internal timing
- **THEN** the lines SHALL carry the `[DIAG]` tag and SHALL NOT be consumed by `measure.sh` as a metric source

