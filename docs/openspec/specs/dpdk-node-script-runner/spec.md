# dpdk-node-script-runner Specification

## Purpose
TBD - created by archiving change full-dpdk-endpoint-interfaces. Update Purpose after archive.
## Requirements

### Requirement: Orchestrator starts each VM using its node script via SSM
The orchestrator SHALL invoke `nodes/server.sh`, `nodes/servernic.sh`, and `nodes/clientnic.sh` on their respective VMs via SSM `send-command`, wrapping each in `setsid bash ... < /dev/null >> /tmp/<vm>.log 2>&1 &` so it runs as a background daemon.

#### Scenario: Node scripts launched in correct order
- **WHEN** the orchestrator runs
- **THEN** Server node script is started first, followed by ServerNIC, then ClientNIC (with the GW MAC argument), each via SSM

#### Scenario: ClientNIC node script receives GW MAC argument
- **WHEN** the orchestrator launches `nodes/clientnic.sh`
- **THEN** it passes the GW MAC as `$1` so `clientnic.sh` does not need to query the EC2 API from the VM

### Requirement: GW MAC is discovered by the orchestrator via SSM
The orchestrator SHALL discover the ServerNIC's eth0 MAC by reading `/sys/class/net/eth0/address` on the ServerNIC VM via SSM, before launching ClientNIC.

#### Scenario: MAC read successfully
- **WHEN** ServerNIC is running
- **THEN** `cat /sys/class/net/eth0/address` returns a valid MAC address and the orchestrator passes it to `clientnic.sh`

#### Scenario: MAC read fails
- **WHEN** the SSM command returns empty or "None"
- **THEN** the orchestrator exits with a clear error before attempting to start ClientNIC

### Requirement: Client test runs non-interactively via client.py
The orchestrator SHALL run the client test by calling `client.py --mode repeated --count 1` directly on the Client VM via SSM, bypassing `client.sh`'s interactive read loop.

#### Scenario: Client test succeeds
- **WHEN** `client.py --mode repeated --count 1 --verbose` exits 0
- **THEN** the orchestrator records a pass and captures stdout for the report

#### Scenario: Client test fails
- **WHEN** `client.py` exits non-zero or output does not match `Success: 1/1`
- **THEN** the orchestrator records a failure and includes client stdout in the report

### Requirement: Git safe.directory is configured before git pull on each VM
Before running `git pull` on any VM, the orchestrator SHALL execute `git config --global --add safe.directory /home/ec2-user/zero-rtt-tcp` to prevent ownership errors when running as root via SSM.

#### Scenario: Pull succeeds as root
- **WHEN** the orchestrator runs git pull on a VM
- **THEN** git does not emit a "dubious ownership" error and the pull completes

### Requirement: Per-VM logs are captured and displayed
The orchestrator SHALL fetch `/tmp/server.log`, `/tmp/servernic.log`, `/tmp/clientnic.log` from each VM via SSM after the client test completes, and print them to stdout.

#### Scenario: Logs collected after test
- **WHEN** the client test has completed
- **THEN** the orchestrator fetches and prints each VM's log before running the validator

### Requirement: Report is saved to experiments/dpdk/reports/
After all checks, the orchestrator SHALL write a Markdown report summarising pass/fail results and key log excerpts to `experiments/dpdk/reports/integration-test-report-<YYYY-MM-DD>.md`.

#### Scenario: Report written on success
- **WHEN** all checks pass
- **THEN** a report file is created in `experiments/dpdk/reports/`

#### Scenario: Report written on failure
- **WHEN** one or more checks fail
- **THEN** a report file is still created, noting which checks failed

### Requirement: Orchestrator discovers and passes next-hop and port-identity MACs
Because the endpoint-facing SmartNIC ports are DPDK (no ARP, and no kernel netdev to read), the orchestrator SHALL discover — via EC2 `describe-instances` (or `/sys/class/net/*/address` over SSM on the RUNS lab) — and pass to the SmartNIC node scripts:

- **Next-hop (peer) MACs**, used as TX destinations: the ServerNIC's Middle-subnet ENI MAC (to ClientNIC as `--gw-mac`), the ClientNIC's Middle-subnet ENI MAC (to ServerNIC as `--gw-mac`), and the Server's ENI MAC (to ServerNIC as `--server-mac`).
- **Port-identity MACs**, used to resolve which DPDK port plays which role: each SmartNIC's own two data-ENI MACs (as `--client-port-mac` / `--server-port-mac`).

The Client's MAC SHALL NOT be discovered or passed: the ClientNIC learns it per-flow from the SYN.

#### Scenario: MACs discovered and passed
- **WHEN** the orchestrator launches the SmartNIC node scripts
- **THEN** each SmartNIC SHALL receive both its next-hop MACs and its own two DPDK port MACs

#### Scenario: MAC discovery fails
- **WHEN** any required MAC resolves empty or "None"
- **THEN** the orchestrator SHALL exit with a clear error naming the variable, before launching the affected SmartNIC

#### Scenario: No kernel-name-based DPDK rebinding at startup
- **WHEN** a SmartNIC node script starts
- **THEN** it SHALL NOT attempt to detect or "fix" which kernel interface is DPDK-bound — port roles are resolved by the binary from the port-identity MACs, and a name-based rebind under dual-DPDK would unbind an arbitrary vfio device

### Requirement: No SmartNIC-side packet capture on DPDK-owned interfaces
The node scripts SHALL NOT run `tcpdump` on a SmartNIC's endpoint-facing interface once it is DPDK-bound (the kernel cannot see a vfio-pci NIC). Metrics SHALL be sourced from the Client and Server host captures per the `endpoint-pcap-measurement` model.

#### Scenario: No tcpdump on the converted interface
- **WHEN** `clientnic.sh` runs with the client-facing interface bound to DPDK
- **THEN** it SHALL NOT start a `tcpdump` on that interface, and analysis SHALL use the Client host's `/tmp/client_side.pcap`
