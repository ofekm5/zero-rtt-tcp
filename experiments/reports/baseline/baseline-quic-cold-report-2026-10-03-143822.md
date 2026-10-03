# QUIC cold Report — 2026-10-03-143822

**Mode**: QUIC cold (`PROTO=quic QUIC_RESUME=0`, `experiments/nodes/loadgen_quic.py`, aioquic)
**Infra**: `infra/baseline` CDK stack (BaselineStack) — 4× t3.micro, kernel forwarding
**Overall result**: ALL PASSED ✅

## Load Parameters

These must match the TCP baseline, 0-RTT TCP and the other QUIC run being
compared against, or the four-arm comparison is confounded.

| Parameter | Value |
|---|---|
| `PROTO` | quic |
| `QUIC_RESUME` | 0 (cold) |
| Rounds | 1 |
| `LOAD_PARALLEL` | 2000 |
| `LOAD_PORTS` | 4 |
| `LOAD_BYTES` | 1024 |
| `LOAD_RATE` | 100 conn/s |
| `LOAD_CONCURRENCY` | 2000 |
| `NETEM_RTT_MS` | 100 (ClientNIC↔ServerNIC leg, half per direction) |

`LOAD_THINK_MS` does not apply: `loadgen_quic.py` has no think-time knob.

## Latency Summary

```
  ── Primary: time-to-first-byte the client actually experiences ──
  quic_summary mode=cold n=2000 send_unlock_p50_ms=105.454 send_unlock_p95_ms=175.481 handshake_p50_ms=105.454 early_data_accepted=0/2000
  (app-side send_unlock from loadgen_quic.py; QUIC is encrypted, so no pcap fct/server_gap)
```

## Client Output

```
--- Round 1/1: 4 port(s) starting at 8080 x 2000 total connections, 1024 bytes/conn, 100 conn/s arrival, QUIC cold, max 2000 in flight ---
Arrival: rate=100 conn/s requested, 100 conn/s achieved over 19.990s
Transfer complete: 2000/2000 connections ok, 0 failed, duration=21.952s
Success: 2000/2000
quic_summary mode=cold n=2000 send_unlock_p50_ms=105.454 send_unlock_p95_ms=175.481 handshake_p50_ms=105.454 early_data_accepted=0/2000
Success: 1/1
```

## Server Log

```
[1;33m[14:37:40] Killing any leftover load-generator processes...[0m
[1;33m[14:37:41] Open-file limit (ulimit -n): 1048576[0m
[1;33m[14:37:41] Syncing code to origin/experiments/quic-comparison-2026-10-03 (hard reset ? discards VM-local drift)...[0m
From https://github.com/ofekm5/zero-rtt-tcp
 * branch            experiments/quic-comparison-2026-10-03 -> FETCH_HEAD
HEAD is now at a340e31 Merge remote-tracking branch 'origin/main'
[1;33m[14:37:42] Server VM IP: 10.1.2.117[0m
[1;33m[14:37:42] Will listen on 0.0.0.0:8080-8083 (4 port(s))[0m

[1;33m[14:37:42] Starting load-generator server on ports 8080-8083 ? press Ctrl+C to stop.[0m

Generating a 2048 bit EC private key
writing new private key to '/tmp/quic.key'
-----
Listening on ports [8080, 8081, 8082, 8083]
Received 2049024 bytes across 2001 connections (final)
```

## Notes

- **Plaintext vs encrypted.** The TCP baseline and 0-RTT TCP arms are plaintext;
  QUIC always encrypts. `send_unlock` here includes the TLS 1.3 handshake work
  the TCP arms never do.
- **One ticket, reused.** Each client process makes one priming connection and
  every resumed flow reuses its session ticket, so all resumed flows are
  "returning users".
- **Different data plane for the 0-RTT TCP arm.** TCP baseline, QUIC cold and QUIC
  resumed run on this kernel-routed baseline stack; 0-RTT TCP runs on the DPDK
  stack, so NIC-side processing differences land inside that arm's number.
- **Metric.** `send_unlock` is app-side (connect start → first write permitted),
  taken on the client's own clock by `loadgen_quic.py`. No pcap capture and no
  `analyze_metrics.py` run for QUIC; `fct` and `server_gap` are not measured.
- **A2 escalation triggers** — read off the `quic_summary` line above; if any
  holds, add the pcap header cross-check:
  - cold `send_unlock_p50_ms` is not near `NETEM_RTT_MS` (100);
  - resumed `send_unlock_p50_ms` is not clearly below cold;
  - `early_data_accepted` is below n/n on a resumed run (expected 0/n cold);
  - resumed `handshake_p50_ms` equals cold (resumption silently fell back).
- Traffic path: Client → ClientNIC (kernel forward) → ServerNIC (kernel forward) → Server, UDP.
