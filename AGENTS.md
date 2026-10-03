# Repository guidance

Educational 0-RTT TCP proof of concept, not a production service. Live code is
C11 + DPDK 23.11 on AWS EC2; Scapy is deprecated. BlueField-3 DOCA/DPDK work is
a separate platform track. `roadmap.md` is the source of truth for current work.

## Working agreements

- Lead non-code replies with the finding or next step. Default to bullets, at
  most five with two sentences each; simple answers need at most three sentences.
  Explain why only when it changes a decision. Use diagrams when they shorten
  an explanation, and state uncertainty with the evidence needed to resolve it.
- Touch only the requested scope; preserve unrelated local changes.
- Define a concrete completion check up front, run it, and report its output
  before claiming success. Distinguish offline checks from live experiments.
- Read the relevant `.agents/skills/<name>/SKILL.md` before using its workflow.
  Project skills: `$run-experiment`, `$offline-analysis`, `$runs-lab-connect`.
- Use `infra/*/deploy.ps1` and `infra/*/destroy.ps1` for CDK lifecycle operations;
  do not substitute direct WSL deployments.
- Never fabricate benchmark reports or close AWS tasks using mock-test evidence.

## Live architecture

```text
Client -> ClientNIC -> ServerNIC -> Server
          spoof + stamp  translate + buffer
```

- `experiments/nodes/loadgen.py`: asyncio TCP client/server with paced arrivals.
- `src/clientnic/dpdk-forwarder/`: spoof SYN-ACK with ISN V, stamp V into the
  forwarded SYN's ACK field, then forward transparently.
- `src/servernic/dpdk/`: extract V, compute `delta = V - real_server_isn`, drop
  the real SYN-ACK, buffer early data until the real handshake is ready.
  Client-to-server ACKs subtract delta; server-to-client SEQs add delta.
- Legacy `src/{clientnic,servernic}/scapy/` has different flow ownership. Do not
  apply its ClientNIC translation model to the live DPDK path.
- Each SmartNIC has two DPDK ENA data ports and a kernel management ENI for SSM.
  Resolve port roles by MAC, not PCI enumeration or interface name; never bind
  the management ENI to vfio-pci.

Flow keys are four-tuples. Sequence arithmetic wraps modulo 2^32. Recalculate
IP/TCP checksums after rewriting. Endpoint TCP applications remain unmodified.
The middleware is TCP-only, with no TCP options (SACK/timestamps/window scaling),
reliable loss recovery, encryption, or authentication. QUIC runs over UDP only
on the kernel-routed baseline, not through the middleware.

## Repository map

```text
experiments/run.sh       One orchestrator: STACK x TRANSPORT, optional PROTO
experiments/nodes/       VM scripts, TCP/QUIC load generators, metric analyzer
experiments/lib/         Orchestration, measurement, reports, SSM/SSH transports
experiments/tests/       Offline pytest tests, including real loopback QUIC
experiments/reports/     Current reports: 0rtt/ and baseline/
experiments/ci-results/  Timestamped CI bundles and latest pointers
infra/                  CDK stacks, PowerShell lifecycle scripts, BlueField docs/examples
docs/openspec/           Capability specs, active changes, archived changes
docs/superpowers/        Dated design/plan pairs
docs/kb/                Markdown knowledge base
.agents/skills/         Project workflows, references, and helpers
```

`experiments/dpdk/reports/` and `experiments/baseline-tcp/reports/` are frozen
historical output. New reports belong in `experiments/reports/<stack>/`.

## Validation

Use the existing repo-root `venv` when available. Experiment tests need `pytest`,
`pyyaml`, and `aioquic==1.3.0`; QUIC needs Python >=3.10. Amazon Linux 2 endpoints
keep system Python for TCP; `nodes/ensure_quic_python.sh` provisions a separate
CPython 3.11 venv for QUIC without changing the AMI or kernel.

```powershell
# Put Git Bash before the System32 WSL bash launcher for Windows shell tests.
$env:PATH = 'C:\Program Files\Git\bin;' + $env:PATH
& .\venv\Scripts\python.exe -m pytest experiments/tests -q
```

```bash
python -m pytest experiments/tests -q
python -m pytest src/clientnic/dpdk-forwarder/tests/test_forwarder.py src/servernic/dpdk/tests -q
```

Select checks relevant to the change. DPDK builds and virtual-PMD smoke tests
need Linux/DPDK; read component test READMEs. Transport mocks verify orchestration
calls, not packet behavior. Data-plane claims need a live run.

## AWS lifecycle and experiments

Region: `eu-central-1`. From the repository root:

```powershell
& .\infra\baseline\deploy.ps1
& .\infra\dpdk\deploy.ps1
# Add -Bootstrap only when CDKToolkit is absent.
# After an authorized experiment, tear down its disposable stacks:
& .\infra\baseline\destroy.ps1 -Force
& .\infra\dpdk\destroy.ps1 -Force
```

Baseline stacks: `BaselinePacketTestStack`, `BaselineStack`, tags `baseline-*`.
DPDK stacks: `PacketTestStack`, `SmartNicsStack`, tags `smartnics-*`.
Baseline boots quickly; DPDK user data builds dependencies (~15-20 minutes).
Match endpoint VM types before comparing; current templates use `t3.micro`
baseline endpoints and `m5.xlarge` DPDK endpoints.

Use `run-experiment` for live experiments. GitHub Actions is the default AWS
path and saves a full results bundle:

```bash
gh workflow run run-experiment.yml -f infra=both -f load_parallel=2000 -f load_rate=500
```

Always pass connection count and rate explicitly. Defaults are 100,000 at
2,000/s, a capacity workload whose queueing invalidates latency claims. Match
all load knobs and `NETEM_RTT_MS` across compared arms. QUIC requires
`STACK=baseline PROTO=quic QUIC_RESUME=0|1`; calibrate `--mode rate-spike` and
reduce the rate instead of inheriting TCP defaults.

Local TCP: `LOAD_PARALLEL=2000 LOAD_RATE=500 ./experiments/run.sh`; add
`STACK=baseline` for plain TCP or `TRANSPORT=ssh` for the lab. Startup order is
Server -> ServerNIC -> ClientNIC -> Client. Let the orchestrator capture, analyze,
and write its report. Exit code equals failed checks. After CI, use
`offline-analysis` on both bundles and verify matching knobs before quoting gains.
The workflow commits results to its dispatch ref. For PR-protected main, use
`--ref` with a writable experiment branch and pass `repo_ref` explicitly;
preserve repository rules. Download Actions artifacts if publication fails.
The workflow requires `AWS_ROLE_ARN`; this checkout has no `aws-ops.yml`
deployment workflow or deployment request-file protocol.

## Measurement and documentation

- Read `experiments/measurement-methodology-review.md` before changing netem,
  RTT, or interpreting FCT. Delay belongs on the ClientNIC-to-ServerNIC middle
  leg; endpoint-side delay can erase the FCT gain.
- TCP `send_unlock`, FCT, and `server_gap` come from endpoint pcaps through
  `experiments/nodes/analyze_metrics.py`. NIC logs are diagnostic. A `missing=`
  event is a failed metric check.
- QUIC `send_unlock` uses the client's clock. Check early-data acceptance,
  retain handshake timing, state plaintext/encrypted and reused-ticket caveats,
  and evaluate A2 triggers in the QUIC design.
- Read `docs/kb/wiki/Capacity Model.md` before changing sizing or running at scale.
- `docs/index.html` is the results write-up; `docs/results-review.html` explains
  methodology. Reports and CI bundles are evidence, not hand-authored substitutes.
- Start knowledge-base navigation at `docs/kb/index/index.md`. Current capability
  specs are in `docs/openspec/specs/`; active changes and archives are in
  `docs/openspec/changes/`. Preserve existing plan/design conventions.

Use `runs-lab-connect` for lab access. Its current reference describes direct
OpenVPN access; `ssh_lab.sh` may still rely on configured `runs-gateway` plumbing.
Inspect the transport and SSH configuration before treating them interchangeably.
Keep credentials and VPN profiles outside version control.
