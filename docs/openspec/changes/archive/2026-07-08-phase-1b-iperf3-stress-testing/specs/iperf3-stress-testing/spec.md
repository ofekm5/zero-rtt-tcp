## ADDED Requirements

### Requirement: iperf3 installed on Client and Server VMs
Client and Server VMs SHALL have iperf3 available at launch via CDK user data in both the dpdk and scapy stacks.

#### Scenario: iperf3 available after VM launch
- **WHEN** a Client or Server VM is launched from the CDK stack
- **THEN** `iperf3 --version` executes successfully on the VM

### Requirement: iperf3 server node script
A node script `iperf3-server.sh` SHALL start an iperf3 server on port 5201 in daemon mode, killing any existing instance first. The script SHALL be present in both `experiments/zero-rtt-dpdk/nodes/` and `experiments/zero-rtt-clientnic-translate/nodes/`.

#### Scenario: Server script kills existing iperf3 before starting
- **WHEN** `iperf3-server.sh` is executed and iperf3 is already running
- **THEN** the existing process is killed and a fresh iperf3 server starts on port 5201

#### Scenario: Server script starts iperf3 daemon with JSON logging
- **WHEN** `iperf3-server.sh` is executed
- **THEN** iperf3 runs as a daemon with `--json-output` and logs to `/tmp/iperf3_server.log`

### Requirement: iperf3 client node script
A node script `iperf3-client.sh` SHALL accept a server IP as first argument and optional iperf3 flags, run iperf3 against port 5201 with JSON output (`-J`), and print results to stdout. The script SHALL be present in both experiment node directories.

#### Scenario: Client script runs with server IP
- **WHEN** `iperf3-client.sh <server-ip>` is executed
- **THEN** iperf3 connects to `<server-ip>:5201`, completes a default 10s TCP test, and prints JSON to stdout

#### Scenario: Client script passes through extra flags
- **WHEN** `iperf3-client.sh <server-ip> -P 4` is executed
- **THEN** iperf3 runs 4 parallel streams and includes all stream results in JSON output

### Requirement: iperf3 experiment orchestrator
`experiments/zero-rtt-dpdk/run_iperf3_experiment.sh` SHALL orchestrate a full iperf3 stress test through the 0-RTT DPDK path: discover instances, start components in order, run a 4-scenario test matrix, collect results, and write a markdown report.

#### Scenario: Orchestrator starts components in correct order
- **WHEN** `run_iperf3_experiment.sh` is executed
- **THEN** components start in order: iperf3 server → ServerNIC → ClientNIC DPDK (with `--port=5201`) → iperf3 client tests

#### Scenario: Orchestrator runs 4-scenario test matrix
- **WHEN** the orchestrator reaches the test phase
- **THEN** it runs all four scenarios: single stream TCP, 4 parallel streams (`-P 4`), reverse mode (`-R`), and bidirectional (`--bidir`), each for 10 seconds

#### Scenario: Orchestrator writes markdown report
- **WHEN** all test scenarios complete
- **THEN** a report is written to `experiments/zero-rtt-dpdk/reports/iperf3-report-YYYY-MM-DD.md` containing throughput, retransmits, and stream counts from each scenario

#### Scenario: Orchestrator falls back to SSM install if iperf3 missing
- **WHEN** iperf3 is not found on the Client or Server VM
- **THEN** the orchestrator installs it via SSM before proceeding with tests
