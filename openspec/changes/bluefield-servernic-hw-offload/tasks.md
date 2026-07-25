## Tasks

New meson target at `src/servernic/bluefield/`, reusing `flow_table.c`, `syn_handler.c`, and `checksum.c` from `src/servernic/dpdk/` by reference. The existing `servernic-dpdk` target and its AWS path are not modified.

Verify hints check the artifact itself, matching the existing `src/servernic/dpdk/tests/` pattern of Python tests that need no DPDK toolchain. Tasks whose outcome is only observable on the DPU are marked `manual review` — the sandboxed verifier has no lab access, no DPDK headers, and no aarch64 cross-toolchain.

- [ ] 1. Add the `servernic-bluefield` meson target reusing shared modules — verify: `grep -q "servernic-bluefield" src/servernic/bluefield/meson.build && grep -q "servernic/dpdk/flow_table.c" src/servernic/bluefield/meson.build`
    - File: `src/servernic/bluefield/meson.build`
    - Outcome: a target named `servernic-bluefield` builds from new sources plus `flow_table.c`, `syn_handler.c`, and `checksum.c` referenced from `src/servernic/dpdk/` rather than copied, so a T8 protocol fix lands once. `translator.c` is deliberately not among the sources — the hardware rules replace it, per `design.md` D4.
    - Commit: `feat(servernic-bluefield): add meson target reusing shared T8 modules`

- [ ] 2. Bind mlx5 representor ports on the DPU ARM — verify: `grep -q "rte_eth_rx_burst" src/servernic/bluefield/io.c && grep -q "pf0hpf" src/servernic/bluefield/io.c`
    - File: `src/servernic/bluefield/io.c`, `src/servernic/bluefield/io.h`
    - Outcome: initialises the host-facing representor port as a DPDK port and exposes burst receive and transmit over it, replacing the ENA and AF_PACKET pair used on AWS. Single-port operation: receive and transmit use the same port, since `p0` has no carrier and the card has no `p1`.
    - Commit: `feat(servernic-bluefield): bind mlx5 representor port for single-port I/O`

- [ ] 3. Compose the directional hardware rule pair for a flow — verify: `grep -q "tcp_seq_num" src/servernic/bluefield/offload.c && grep -q "tcp_ack_num" src/servernic/bluefield/offload.c`
    - File: `src/servernic/bluefield/offload.c`, `src/servernic/bluefield/offload.h`
    - Outcome: given a flow's 5-tuple and delta, composes two transfer-domain `rte_flow` rules — client-to-server subtracting the delta from the TCP acknowledgment number, server-to-client adding it to the sequence number — both carrying a counter action and both derived from the same delta value. The egress action is a single point in the composition so a Scalable Function target can replace the same-port return without touching match or modify logic, per `design.md` risk mitigation.
    - Commit: `feat(servernic-bluefield): compose directional rte_flow rule pair per flow`

- [ ] 4. Install and tear down per-flow rules across the connection lifecycle — verify: `grep -q "rte_flow_destroy" src/servernic/bluefield/offload.c && grep -q "rte_flow_create" src/servernic/bluefield/offload.c`
    - File: `src/servernic/bluefield/offload.c`
    - Outcome: installs a flow's rule pair exactly once when its delta becomes known, removes both rules on FIN or RST, and records an installation failure without marking the flow as offloaded. Installed rule count tracks live connections so it returns to baseline after connections close.
    - Commit: `feat(servernic-bluefield): manage per-flow rule install and teardown`

- [ ] 5. Dispatch handshake packets only, and count non-handshake receipts — verify: `grep -q "non_handshake_rx" src/servernic/bluefield/pipeline.c`
    - File: `src/servernic/bluefield/pipeline.c`, `src/servernic/bluefield/pipeline.h`
    - Outcome: classifies received packets and dispatches SYN, SYN-ACK, FIN, and RST to their handlers; every packet that is none of these increments a dedicated, externally readable counter. That counter staying at zero is the only measurement that proves data packets bypassed software, per `design.md` D5 — without it Success Criterion 3 is unfalsifiable.
    - Commit: `feat(servernic-bluefield): dispatch handshake packets and count non-handshake receipts`

- [ ] 6. Wire the control plane entry point together — verify: `grep -q "pipeline_feed" src/servernic/bluefield/main.c && grep -q "offload" src/servernic/bluefield/main.c`
    - File: `src/servernic/bluefield/main.c`
    - Outcome: EAL initialisation, CLI arguments for the representor port and peer MACs, and a poll loop that feeds received packets into the pipeline; buffered pre-delta packets are rewritten in software and flushed when the delta is computed, then the flow's hardware rules are installed. Counters for rule count and non-handshake receipts are readable at runtime.
    - Commit: `feat(servernic-bluefield): add EAL init, CLI, and control-plane poll loop`

- [ ] 7. Add tests for rule-pair direction semantics and delta arithmetic — verify: `python -m pytest src/servernic/bluefield/tests/ -q`
    - File: `src/servernic/bluefield/tests/test_rule_pair.py`
    - Outcome: asserts that for a given delta the client-to-server rule subtracts from the acknowledgment number and the server-to-client rule adds to the sequence number, that both derive from the same delta, and that the arithmetic wraps at 32 bits — mirroring the existing `src/servernic/dpdk/tests/test_seq_arith.py` pattern so the tests need no DPDK toolchain.
    - Commit: `test(servernic-bluefield): cover rule-pair direction and 32-bit wraparound`

- [ ] 8. Document the DPU target and its measurement contract — verify: `test -s src/servernic/bluefield/README.md && grep -q "pf0hpf" src/servernic/bluefield/README.md`
    - File: `src/servernic/bluefield/README.md`
    - Outcome: states which modules are shared with `src/servernic/dpdk/` and why `translator.c` is not, the single-port constraint and its cause, how to read the rule count and non-handshake counters, and the blocking dependency on the `verify-eswitch-tcp-seq-offload` verdict.
    - Commit: `docs(servernic-bluefield): document DPU target and measurement contract`

- [ ] 9. Build the target on the DPU ARM — manual review
    - File: `src/servernic/bluefield/` (build performed on 10.13.36.16)
    - Outcome: `meson setup builddir && ninja -C builddir` exits 0 on the DPU against the DPDK under `/opt/mellanox/dpdk`, producing a `servernic-bluefield` binary. Requires the RUNS lab tunnel and an ARM toolchain, so the sandboxed verifier cannot run it.
    - Commit: `chore(servernic-bluefield): record successful ARM build`

- [ ] 10. Verify hardware offload and teardown against live traffic — manual review
    - File: `src/servernic/bluefield/README.md` (measurement results recorded alongside the target)
    - Outcome: with a connection established through the DPU, rule counters increment while the non-handshake receipt counter stays at zero; an iperf transfer completes and a capture confirms server-to-client SEQ carries the delta; and `flow list 0` returns to its pre-run count after N connections open and close. Depends on the separate lab deployment change providing a running client, server, and ClientNIC.
    - Commit: `docs(servernic-bluefield): record hardware offload and teardown measurements`
