# DPDK header stubs

Minimal stand-ins for the `<rte_*.h>` headers, so `wan_delay.c` can be compiled
and unit-tested with plain `cc` — no DPDK, no hugepages, no NIC, no root.

They shadow the real headers because the test compiles with `-Istubs` ahead of
any DPDK include path. Only the symbols `wan_delay.c` (and the `log.h` it pulls
in) actually reference are provided. Anything beyond that is deliberately
missing: a new DPDK dependency should fail loudly at compile time here rather
than be silently satisfied by a stub that behaves differently from the real
thing.

These are for the ring-logic test only. Everything that touches a real port
(`io.c`, `main.c`, the pipeline) is covered by `run_dpdk_tests.sh`, which needs
a real DPDK build.

    cc -Istubs -I.. -o /tmp/test_wan_delay test_wan_delay.c ../wan_delay.c
    /tmp/test_wan_delay
