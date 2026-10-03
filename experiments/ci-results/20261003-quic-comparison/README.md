# Four-arm QUIC comparison — 2026-10-03

All four final arms passed every harness check and completed 2,000/2,000
connections. They used one round, 100 arrivals/s (also achieved), 1,024 bytes,
four ports, 2,000 max in flight, timeout 300 s, and 100 ms modeled RTT on the
middle leg only. `comparison.json` records the selected bundles and numbers.

| Arm | Median send_unlock (ms) | p95 (ms) | Bundle | CI run |
| --- | ---: | ---: | --- | --- |
| Plain TCP | 101.007 | 101.193 | [15:15 baseline](../20261003-151532-baseline/run-meta.json) | [37132329709](https://github.com/ofekm5/zero-rtt-tcp/actions/runs/37132329709) |
| DPDK 0-RTT TCP | 0.338 | 0.364 | [14:55 DPDK](../20261003-145545-dpdk/run-meta.json) | [37130800427](https://github.com/ofekm5/zero-rtt-tcp/actions/runs/37130800427) |
| QUIC cold | 104.395 | 111.857 | [15:01 baseline](../20261003-150149-baseline/run-meta.json) | [37131539950](https://github.com/ofekm5/zero-rtt-tcp/actions/runs/37131539950) |
| QUIC resumed | 1.436 | 2.326 | [15:07 baseline](../20261003-150711-baseline/run-meta.json) | [37131827026](https://github.com/ofekm5/zero-rtt-tcp/actions/runs/37131827026) |

All four endpoints were **m5.xlarge**. Baseline NICs were t3.micro, DPDK NICs
c5n.large. [AWS instance evidence](../20261003-quic-calibration/matched-instance-types.json)
overrides the generated baseline reports' hardcoded “4× t3.micro” label.
Both stack families were deployed and destroyed using their PowerShell
lifecycle scripts. The baseline comparison assembly overrode only the two
endpoint instance types before synthesis; committed infra source is unchanged.

The final loopback spike sustained the highest tested rate, 3,200/s, with
p95 lag 11.170 ms. The lower 100/s rate was retained after the initial t3.micro
delayed-path cold run underfilled 500/s. Cold-run active CPU averaged 32.156%
client and 22.730% server of one core, with 250 ms sample maxima 55.6%/43.7%.
[Calibration and CPU evidence](../20261003-quic-calibration/README.md).

The workflow dispatches used `experiments/quic-comparison-2026-10-03` to save
results without bypassing main's PR requirement. Bundle commit SHAs and the
DPDK VM SHA differ because results were committed between runs. The
experiment code under `src/`, `experiments/nodes/`, `experiments/lib/`,
`experiments/run.sh`, and the workflow is identical to source revision
`a340e3130774295cc91a2c7e27b97fa921b20be0` across selected runs.

TCP `send_unlock` is first SYN to first payload in the client pcap; QUIC is
connect start to first write permitted on the client's monotonic clock.
They address sending permission at different instrumentation boundaries.
TCP is plaintext; QUIC encrypts and includes TLS processing, with a throwaway
self-signed certificate and disabled certificate verification in this harness.
All resumed flows reuse one primed ticket; each QUIC process also makes one
unmeasured priming connection. The baseline routes in the kernel and the
0-RTT arm uses DPDK. Those software and NIC hardware differences remain
confounds when comparing sub-millisecond processing costs.

This is one run per arm. It is not pooled with the historical 500/s TCP series,
does not measure QUIC FCT or server gap, and makes no general throughput claim.
QUIC skips capture: pcap inventories in its saved node logs are old TCP captures,
not QUIC wire evidence. DPDK diagnostic NIC logs hit SSM's output cap and
in-app NIC TTFB samples were unavailable; the headline endpoint metrics cover
all 2,000 flows and neither endpoint capture reports kernel drops. The TCP
server emits a `CancelledError` during shutdown after reporting all 2,000
payloads received; no client transfer or endpoint metric failed.

| A2 trigger from the plan | Evaluation |
| --- | --- |
| Cold send_unlock far from modeled RTT | No: median 104.395 ms versus 100 ms |
| Resumed send_unlock not clearly below cold | No: 1.436 versus 104.395 ms |
| Fewer than all resumed flows accept early data | No: 2,000/2,000 accepted |
| Resumed handshake equal to cold | Similar: 104.827 versus 104.395 ms; conservatively queue A2 |

The fourth trigger is recorded as a follow-up, not as evidence of fallback.
The full handshake still exchanges messages after early sending; its duration
need not disappear with 0-RTT ([RFC 9001 §2.1](https://www.rfc-editor.org/rfc/rfc9001.html#section-2.1)).
All resumed flows report early-data acceptance. A2 remains unimplemented and
requires a fresh QUIC capture with long-header type and first short-header
timing; the current bundles cannot supply that cross-check.
