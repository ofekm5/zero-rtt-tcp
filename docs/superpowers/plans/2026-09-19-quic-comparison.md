# QUIC comparison

**Goal:** Add QUIC cold and QUIC resumed arms on the baseline stack and report client-side `send_unlock` for four arms: TCP baseline, 0-RTT TCP, QUIC cold, QUIC resumed.

**Architecture:** a new `experiments/utils/loadgen_quic.py` runs an `aioquic` client/server that times connect-start to first-write-allowed on the client's own clock; the node scripts and `experiments/run.sh` select it with `PROTO=quic` on `STACK=baseline`. All four arms run at a lower arrival rate found by a loopback spike. No NIC VM or `src/` change — UDP rides the existing kernel-routed baseline path and its `netem` delay.

**Tech Stack:** Python 3 + `aioquic` + pytest, Bash.

**Spec:** `docs/superpowers/specs/2026-09-19-quic-comparison-design.md`

**Global Constraints:**
- Depends on `docs/superpowers/plans/2026-09-08-streamline-experiments-harness.md`: `experiments/run.sh` and `experiments/nodes/` must already exist. Do not start before it lands.
- No change to `src/`, the DPDK stack, `analyze_metrics.py`, or `loadgen.py` (it stays byte-identical).
- Every `verify:` command runs offline — no AWS, no live VMs, no Docker. The QUIC test uses loopback.
- The metric is app-side `send_unlock` only (approach A1). `fct`, `server_gap` and pcap parsing of QUIC are out of scope.
- **Escalation (A2):** if the A1 results do not look good, add a wire cross-check as a follow-up change. "Not good" means any of: cold `send_unlock` not near `NETEM_RTT_MS`; resumed not clearly below cold; early data accepted on fewer than all resumed connections; resumed `handshake_ms` equal to cold. A2 reads the unencrypted QUIC header bits in the client pcap (long-header type 0-RTT, first short-header packet) in `analyze_metrics.py`.

---

- [ ] 1 Write `loadgen_quic.py` — verify: `python3 -c "import ast;ast.parse(open('experiments/utils/loadgen_quic.py').read())" && grep -q 'aioquic' experiments/utils/loadgen_quic.py && git diff --exit-code main -- experiments/utils/loadgen.py`
    - File: `experiments/utils/loadgen_quic.py` (new); `loadgen.py` is not edited
    - Outcome: QUIC client and server with the same paced-arrival shape as `loadgen.py` (`--rate`, `--parallel`, `--bytes`, ports). Flags: `--mode {client,server,rate-spike}`, `--resume`, `--cert`, `--key`. Each client connection records `send_unlock_ms` (connect start until the first write is permitted: handshake complete when cold, immediately after `connect()` returns when resuming), `handshake_ms` (connect start until handshake complete, always) and `early_data_accepted` (from the aioquic TLS state; check the attribute name against the installed version). One priming cold connection per process saves a session ticket; with `--resume` every later connection reuses it. The server sets `max_early_data` and keeps tickets in memory. At exit the client prints `quic_summary mode=<cold|resumed> n=<N> send_unlock_p50_ms=<x> send_unlock_p95_ms=<x> handshake_p50_ms=<x> early_data_accepted=<k>/<N>`.
    - Commit: `feat(experiments): add QUIC load generator with per-connection send_unlock`

- [ ] 2 Pin cold-vs-resumed on loopback — verify: `pytest experiments/tests/test_loadgen_quic.py -q`
    - File: `experiments/tests/test_loadgen_quic.py` (new); skip with a clear reason if `aioquic` is not importable
    - Outcome: starts the QUIC server on `127.0.0.1`, runs a cold and a resumed client (small `n`), and asserts the resumed `send_unlock_p50_ms` is below the cold one, `early_data_accepted` equals `n` resumed and `0` cold, and the `quic_summary` line parses. It fails if resumption silently falls back to 1-RTT.
    - Commit: `test(experiments): pin QUIC cold vs resumed send_unlock on loopback`

- [ ] 3 Spike: find the sustainable arrival rate — verify: `python3 experiments/utils/loadgen_quic.py --mode rate-spike | grep -q '^sustained_rate='`
    - File: `experiments/utils/loadgen_quic.py` (add a `rate-spike` mode); result recorded in the design's "Not yet specified"
    - Outcome: on loopback, ramps the cold-handshake rate and reports the highest rate at which the event-loop lag stays small (`sustained_rate=<n>`). The rate used for all four runs is about half of it, capped at 500. Record the chosen `RATE` in the design doc. Loopback is faster than a real 4-vCPU VM, so the number is an upper bound; confirm on the first AWS run that client CPU stays well under 100%.
    - Commit: `feat(experiments): add QUIC arrival-rate spike`

- [ ] 4 Run QUIC from the endpoint node scripts — verify: `bash -n experiments/nodes/client.sh && bash -n experiments/nodes/server.sh && grep -q 'loadgen_quic.py' experiments/nodes/client.sh experiments/nodes/server.sh`
    - File: `experiments/nodes/client.sh`, `experiments/nodes/server.sh`
    - Outcome: when `PROTO=quic`, each script `pip install`s `aioquic` if missing and runs `loadgen_quic.py`; the server script first generates a self-signed cert and key with `openssl req -x509 -newkey rsa:2048 -nodes -days 1` into `/tmp` and passes `--cert`/`--key`; the client adds `--resume` when `QUIC_RESUME=1`. With `PROTO` unset both scripts behave as before.
    - Commit: `feat(experiments): run the QUIC load generator from the endpoint scripts`

- [ ] 5 Run the QUIC arm from the orchestrator and report it — verify: `bash -n experiments/run.sh && grep -q 'PROTO' experiments/run.sh && grep -q 'QUIC_RESUME' experiments/run.sh`
    - File: `experiments/run.sh` (and the lib file that prints the latency block, per the layout `streamline-experiments-harness` produced)
    - Outcome: on `STACK=baseline`, `PROTO=quic` starts the QUIC endpoints, captures the client's `quic_summary` line and prints it under the headline tier. Cold and resumed are separate runs (`QUIC_RESUME=0|1`). The report states that TCP and 0-RTT arms are plaintext while QUIC always encrypts, that all resumed flows reuse one ticket, and prints `early_data_accepted` and `handshake_p50_ms` so the escalation triggers can be read off it. Pcap capture and `analyze_metrics.py` are skipped for the QUIC arm.
    - Commit: `feat(experiments): add a QUIC arm to the baseline stack`

- [ ] 6 Run all four arms and write the table up — verify: `ls experiments/baseline-tcp/reports/*quic* | wc -l | grep -qE '^[2-9]' && grep -q 'QUIC' docs/index.html`
    - File: four new reports (TCP baseline, QUIC cold, QUIC resumed under `experiments/baseline-tcp/reports/`; 0-RTT TCP under `experiments/dpdk/reports/`), and `docs/index.html`
    - Outcome: manual, needs AWS. Deploy each stack and run at the same `NETEM_RTT_MS`, connection count and the `RATE` from Task 3. Paste the four `send_unlock` numbers into `docs/index.html` by hand, with the plaintext-vs-encrypted and one-ticket caveats. Check the escalation triggers in Global Constraints against the QUIC reports.
    - Commit: `docs(experiments): add the four-arm QUIC comparison`

- [ ] 7 Record the change and the A2 escalation in the roadmap — verify: `grep -q 'A2' roadmap.md && grep -q 'quic-comparison' roadmap.md`
    - File: `roadmap.md`
    - Outcome: the "QUIC comparison" section links the plan and design, states the framing (0-RTT TCP versus QUIC cold and resumed, `send_unlock` only, reduced rate) and adds a checkbox: "If A1 results look off, add the pcap header cross-check (A2)", with the four triggers.
    - Commit: `docs(roadmap): record the QUIC comparison plan and A2 escalation`

## Sprint Graph

```sprint-graph
{
  "maxParallel": 2,
  "sprints": [
    { "id": 1, "name": "quic loadgen", "tasks": [1, 2, 3], "dependsOn": [], "touches": ["experiments/utils/loadgen_quic.py", "experiments/tests/test_loadgen_quic.py"] },
    { "id": 2, "name": "orchestration", "tasks": [4, 5], "dependsOn": [1], "touches": ["experiments/nodes", "experiments/run.sh"] },
    { "id": 3, "name": "docs", "tasks": [7], "dependsOn": [], "touches": ["roadmap.md"] }
  ],
  "waves": [[1, 3], [2]]
}
```
Task 6 is a manual AWS run and sits outside the sprint graph; it starts after sprint 2.
triage-verdict: ok
