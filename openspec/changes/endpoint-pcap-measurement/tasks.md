## 1. Analyzer — analyze_metrics.py

- [ ] 1.1 Create the offline pcap analyzer — verify: `python3 -m py_compile experiments/utils/analyze_metrics.py && python3 experiments/utils/analyze_metrics.py --help`
    - File: `experiments/utils/analyze_metrics.py`
    - Outcome: a CLI exists taking `--client-pcap` and optional `--server-pcap`, reading via `scapy.rdpcap`, that locates the flow by 4-tuple anchored on the SYN to `server:<port>`. From the client pcap it computes `fct` (first SYN out → last data byte/FIN) and `send_unlock` (first SYN out → first outbound payload>0 segment); from the server pcap it computes `server_gap` (first SYN-ACK out → first inbound payload>0 segment). Reuses the rdpcap + 4-tuple + SYN-timing structure of `clientnic/validate_0rtt_capture.py`. Runs offline (must be runnable from outside any `scapy/`-named dir).
    - Commit: `feat(experiments): add analyze_metrics.py endpoint pcap analyzer`

- [ ] 1.2 Emit metrics as machine-parseable key=value lines — verify: `python3 -m pytest experiments/utils/tests/test_analyze_metrics.py -k output_format`
    - File: `experiments/utils/analyze_metrics.py`
    - Outcome: each metric prints exactly as `metric=<fct|send_unlock|server_gap> value_ms=<v> node=<client|server> flow=<srcip:sport-dstip:dport>`; FCT and send_unlock derive from the same client-pcap flow (one source of truth).
    - Commit: `feat(experiments): emit key=value metric lines from analyzer`

- [ ] 1.3 Add validation guardrails for incomplete captures — verify: `python3 -m pytest experiments/utils/tests/test_analyze_metrics.py -k guardrails`
    - File: `experiments/utils/analyze_metrics.py`
    - Outcome: a flow missing a required event (no SYN, no payload-bearing segment, truncated capture) causes a non-zero exit and/or a printed flag line naming the missing event, instead of emitting a wrong/zero metric.
    - Commit: `feat(experiments): flag incomplete captures in analyzer`

- [ ] 1.4 Add optional iperf CSV FCT cross-check — verify: `python3 -m pytest experiments/utils/tests/test_analyze_metrics.py -k cross_check`
    - File: `experiments/utils/analyze_metrics.py`
    - Outcome: when an `iperf -y C` CSV is provided, the analyzer warns if pcap-derived FCT diverges from iperf2's reported duration by more than 10 ms; pcap value remains authoritative regardless.
    - Commit: `feat(experiments): add iperf CSV FCT cross-check to analyzer`

- [ ] 1.5 Add unit tests building real pcaps with scapy — verify: `python3 -m pytest experiments/utils/tests/test_analyze_metrics.py`
    - File: `experiments/utils/tests/test_analyze_metrics.py`
    - Outcome: tests construct synthetic flows (SYN, SYN-ACK, payload segments, FIN) with scapy, `wrpcap` them to a temp path, and assert the three metric values, the key=value output format, the guardrail behavior, and the cross-check — no DPDK/live infra required.
    - Commit: `test(experiments): unit tests for analyze_metrics.py`

## 2. measure.sh rewrite

- [ ] 2.1 Remove dead [METRIC] grep and parse analyzer output — verify: `bash -n experiments/utils/measure.sh && ! grep -q '\[METRIC\]' experiments/utils/measure.sh`
    - File: `experiments/utils/measure.sh`
    - Outcome: the `summarize_metric`/`[METRIC] … node=… ttfb|fct` parsing is gone; a function consumes `analyze_metrics.py`'s `metric=… value_ms=…` lines and reports `fct`, `send_unlock`, `server_gap`. The report never prints "no samples found" for a valid run.
    - Commit: `refactor(experiments): parse analyzer output in measure.sh`

## 3. Endpoint capture + accuracy knobs (AWS runner)

- [ ] 3.1 Relocate tcpdump to the Client host and add a Server-host capture — verify: `bash -n experiments/dpdk/run_experiment.sh`
    - File: `experiments/dpdk/run_experiment.sh`
    - Outcome: the capture step starts `tcpdump` on the Client host's own data iface → `client_side.pcap` and on the Server host's own iface → `server_side.pcap` (instead of on ClientNIC eth0), bracketing the iperf2 flow (start before connect, stop after completion), filtered to the flow's TCP traffic without excluding SYN/SYN-ACK/FIN, requesting `--time-stamp-precision=nano -j host_hiprec` with graceful fallback.
    - Commit: `feat(experiments): capture pcaps on client and server endpoints`

- [ ] 3.2 Add offload-off + tc netem accuracy knobs before capture — verify: `bash -n experiments/dpdk/run_experiment.sh && grep -q 'netem' experiments/dpdk/run_experiment.sh`
    - File: `experiments/dpdk/run_experiment.sh`
    - Outcome: before capture, both endpoints run `ethtool -K <if> gro off lro off tso off gso off` and `tc qdisc add dev <if> root netem delay 50ms`; the runner logs/asserts the offload state, and tears the netem qdisc down after the run.
    - Commit: `feat(experiments): disable offload and inject netem before capture`

- [ ] 3.3 Replace validator call with analyze_metrics.py and feed measure.sh — verify: `bash -n experiments/dpdk/run_experiment.sh && grep -q 'analyze_metrics.py' experiments/dpdk/run_experiment.sh`
    - File: `experiments/dpdk/run_experiment.sh`
    - Outcome: after capture the runner copies both pcaps off any `scapy/`-shadowing dir, runs `analyze_metrics.py --client-pcap … --server-pcap …` (plus the iperf CSV), and pipes its output into the rewritten `measure.sh`; the report shows the three endpoint metrics.
    - Commit: `feat(experiments): drive analyze_metrics.py from the AWS runner`

- [ ] 3.4 End-to-end AWS run produces the three metrics — manual review
    - Area: `experiments/dpdk/run_experiment.sh` on live AWS (requires SSM access)
    - Outcome: a full run reports non-empty `fct`/`send_unlock`/`server_gap`, with `send_unlock` an order of magnitude below the ~100 ms netem RTT, and no "no samples found".
    - Commit: `test(experiments): AWS endpoint-measurement run report`

## 4. Shared core + Proxmox transport

- [ ] 4.1 Factor the shared runner core — verify: `bash -n experiments/utils/run_core.sh`
    - File: `experiments/utils/run_core.sh` (new)
    - Outcome: a sourceable helper exposes the infra-agnostic flow — "start endpoint captures → run iperf2 → stop captures → copy pcaps → analyze → report" — parameterized by injected node-discovery and exec-transport functions, so AWS and Proxmox runners share it.
    - Commit: `refactor(experiments): extract shared runner core`

- [ ] 4.2 Add the Proxmox SSH-gateway transport — verify: `bash -n experiments/utils/ssh_lab.sh`
    - File: `experiments/utils/ssh_lab.sh` (new)
    - Outcome: an `ssh_run`-style transport mirrors `ssm.sh` but executes on nodes via the runs-gateway jump host against a static `10.13.37.x` inventory (per `.claude/skills/runs-lab-connect/SKILL.md`).
    - Commit: `feat(experiments): add Proxmox SSH-gateway transport`

- [ ] 4.3 Add the Proxmox runner using core + ssh_lab — verify: `bash -n experiments/proxmox/run_experiment.sh`
    - File: `experiments/proxmox/run_experiment.sh` (new)
    - Outcome: the Proxmox runner sources `run_core.sh` and `ssh_lab.sh`, supplies the static inventory and SSH transport, and runs the identical capture→analyze→report path; the AWS runner is refactored to source the same `run_core.sh`.
    - Commit: `feat(experiments): add Proxmox LAN runner on shared core`

- [ ] 4.4 Proxmox run produces the three metrics — manual review
    - Area: `experiments/proxmox/run_experiment.sh` on the RUNS lab (requires gateway access)
    - Outcome: the same analyzer + captures yield `fct`/`send_unlock`/`server_gap` on the 1-middlebox Proxmox path, confirming R1.
    - Commit: `test(experiments): Proxmox endpoint-measurement run report`

## 5. NIC diagnostics relabel

- [ ] 5.1 Relabel ClientNIC rdtsc stamp [METRIC]→[DIAG] — verify: `grep -q '\[DIAG\]' clientnic/dpdk-forwarder/forwarder.c && ! grep -q '\[METRIC\]' clientnic/dpdk-forwarder/forwarder.c`
    - File: `clientnic/dpdk-forwarder/forwarder.c`
    - Outcome: the rdtsc timing log line carries the `[DIAG]` tag; no `[METRIC]` tag remains; data-plane behavior is otherwise unchanged.
    - Commit: `chore(clientnic): relabel rdtsc stamp to [DIAG]`

- [ ] 5.2 Relabel ServerNIC rdtsc stamp [METRIC]→[DIAG] — verify: `grep -q '\[DIAG\]' servernic/dpdk/translator.c && ! grep -q '\[METRIC\]' servernic/dpdk/translator.c`
    - File: `servernic/dpdk/translator.c`
    - Outcome: the rdtsc timing log line carries the `[DIAG]` tag; no `[METRIC]` tag remains; data-plane behavior is otherwise unchanged.
    - Commit: `chore(servernic): relabel rdtsc stamp to [DIAG]`
