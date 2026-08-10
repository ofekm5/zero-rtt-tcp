/* Self-contained check for the emulated-WAN hold queue (wan_delay.c).
 *
 * Compiles with plain `cc` — no DPDK, no hugepages, no NIC, no root. The DPDK
 * headers wan_delay.c includes are shadowed by tests/stubs/, so this exercises
 * the REAL ring logic rather than a reimplementation of it.
 *
 * What is worth testing here is the part that would silently corrupt a
 * measurement: ordering, the release deadline, drop-on-full accounting, ring
 * wraparound, and that a disabled queue is genuinely a no-op. A bug in any of
 * those manufactures packet loss or reordering on the middle leg — exactly the
 * artifact this module exists to avoid (roadmap.md F2).
 *
 * Build & run:
 *   cc -Istubs -I.. -o /tmp/test_wan_delay test_wan_delay.c ../wan_delay.c
 *   /tmp/test_wan_delay
 * Also runs as part of tests/run_dpdk_tests.sh.
 */

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "wan_delay.h"

/* Read by the stubs (tests/stubs/rte_cycles.h, rte_mbuf.h): a test-controlled
 * clock and free counter, so time advances deterministically instead of by
 * sleeping, and the drop path can be asserted to free rather than leak. */
uint64_t g_fake_tsc = 0;
uint64_t g_freed    = 0;

static struct rte_mbuf g_pool[WAN_DELAY_RING * 2];

static struct rte_mbuf *mb(int i) { return &g_pool[i]; }

#define CHECK(cond, msg) do {                                              \
    if (!(cond)) { printf("  FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); \
                   return 1; }                                              \
} while (0)

/* One microsecond of the fake clock. wan_delay_init() derives cycles from
 * rte_get_tsc_hz(), which the stub pins to 1 MHz, so 1 tick == 1 us. */
#define US 1

static int test_disabled_is_a_noop(void)
{
    struct wan_delay w;
    wan_delay_init(&w, 0);
    CHECK(!wan_delay_enabled(&w), "delay_us=0 must leave the queue disabled");
    CHECK(wan_delay_count(&w) == 0, "a fresh queue holds nothing");
    return 0;
}

static int test_packet_is_held_until_its_deadline(void)
{
    struct wan_delay w;
    struct rte_mbuf *out[8];

    g_fake_tsc = 1000;
    wan_delay_init(&w, 50);                    /* 50 us hold */
    CHECK(wan_delay_enabled(&w), "delay_us>0 must enable the queue");

    CHECK(wan_delay_push(&w, mb(0)) == 0, "push must accept into an empty ring");
    CHECK(wan_delay_count(&w) == 1, "pushed packet must be held");

    /* Before the deadline: nothing comes out, no matter how often we poll. */
    CHECK(wan_delay_pop_expired(&w, out, 8) == 0, "must not release early");
    g_fake_tsc += 49 * US;
    CHECK(wan_delay_pop_expired(&w, out, 8) == 0, "must not release 1us early");

    /* At the deadline: released exactly once. */
    g_fake_tsc += 1 * US;
    CHECK(wan_delay_pop_expired(&w, out, 8) == 1, "must release at the deadline");
    CHECK(out[0] == mb(0), "must release the packet that was pushed");
    CHECK(wan_delay_count(&w) == 0, "released packet must leave the ring");
    CHECK(wan_delay_pop_expired(&w, out, 8) == 0, "must not release twice");
    return 0;
}

static int test_order_is_preserved(void)
{
    struct wan_delay w;
    struct rte_mbuf *out[8];

    g_fake_tsc = 0;
    wan_delay_init(&w, 10);

    /* Staggered arrivals => staggered deadlines. Reordering on the middle leg
     * would look like network reordering and corrupt FCT. */
    wan_delay_push(&w, mb(0));
    g_fake_tsc += 3 * US;
    wan_delay_push(&w, mb(1));
    g_fake_tsc += 3 * US;
    wan_delay_push(&w, mb(2));

    /* Deadlines are t=10, t=13, t=16. */
    g_fake_tsc += 4 * US;                      /* t=10: only mb(0) is due */
    CHECK(wan_delay_pop_expired(&w, out, 8) == 1, "only the first is due");
    CHECK(out[0] == mb(0), "first in, first out");

    g_fake_tsc += 4 * US;                      /* t=14: mb(1) due, mb(2) not */
    CHECK(wan_delay_pop_expired(&w, out, 8) == 1, "second becomes due alone");
    CHECK(out[0] == mb(1), "order must be preserved");

    g_fake_tsc += 100 * US;
    CHECK(wan_delay_pop_expired(&w, out, 8) == 1, "third eventually releases");
    CHECK(out[0] == mb(2), "order must be preserved");
    return 0;
}

static int test_max_caps_the_batch(void)
{
    struct wan_delay w;
    struct rte_mbuf *out[4];

    g_fake_tsc = 0;
    wan_delay_init(&w, 10);
    for (int i = 0; i < 10; i++)
        wan_delay_push(&w, mb(i));
    g_fake_tsc += 20 * US;                     /* all due */

    CHECK(wan_delay_pop_expired(&w, out, 4) == 4, "must respect the max arg");
    CHECK(out[0] == mb(0) && out[3] == mb(3), "batch must stay in order");
    CHECK(wan_delay_count(&w) == 6, "the rest must stay queued");
    return 0;
}

static int test_ring_full_drops_and_counts(void)
{
    struct wan_delay w;

    g_fake_tsc = 0;
    g_freed = 0;
    wan_delay_init(&w, 1000);

    for (uint32_t i = 0; i < WAN_DELAY_RING; i++)
        CHECK(wan_delay_push(&w, mb(0)) == 0, "ring must accept up to capacity");
    CHECK(wan_delay_count(&w) == WAN_DELAY_RING, "ring must be exactly full");
    CHECK(w.dropped == 0, "no drops below capacity");

    /* Overflow must be counted and the mbuf freed, never leaked and never
     * silently accepted — a silent drop here manufactures packet loss. */
    CHECK(wan_delay_push(&w, mb(1)) == -1, "push past capacity must fail");
    CHECK(w.dropped == 1, "overflow must increment the drop counter");
    CHECK(g_freed == 1, "the dropped mbuf must be freed, not leaked");
    CHECK(wan_delay_count(&w) == WAN_DELAY_RING, "a drop must not grow the ring");
    return 0;
}

static int test_wraparound(void)
{
    struct wan_delay w;
    struct rte_mbuf *out[64];

    g_fake_tsc = 0;
    wan_delay_init(&w, 10);

    /* Push/pop more than WAN_DELAY_RING packets in total so head and tail wrap
     * past the ring size. An off-by-one in the masking shows up here and
     * nowhere else. */
    uint32_t total = WAN_DELAY_RING + 100;
    uint32_t released = 0;
    for (uint32_t i = 0; i < total; i++) {
        CHECK(wan_delay_push(&w, mb((int)(i % 16))) == 0, "push during wrap");
        g_fake_tsc += 20 * US;
        released += wan_delay_pop_expired(&w, out, 64);
    }
    CHECK(released == total, "every pushed packet must eventually be released");
    CHECK(w.dropped == 0, "steady push/pop must never overflow");
    CHECK(wan_delay_count(&w) == 0, "ring must be empty at the end");
    return 0;
}

static int test_drain_all_ignores_deadlines(void)
{
    struct wan_delay w;
    struct rte_mbuf *out[8];

    g_fake_tsc = 0;
    wan_delay_init(&w, 1000000);               /* 1 s — nothing is due */
    for (int i = 0; i < 5; i++)
        wan_delay_push(&w, mb(i));

    CHECK(wan_delay_pop_expired(&w, out, 8) == 0, "nothing is due yet");
    /* Shutdown must not leak in-flight packets. */
    CHECK(wan_delay_drain_all(&w, out, 8) == 5, "drain_all must release all");
    CHECK(wan_delay_count(&w) == 0, "ring must be empty after drain_all");
    return 0;
}

struct testcase { const char *name; int (*fn)(void); };

int main(void)
{
    struct testcase tests[] = {
        {"disabled queue is a no-op",        test_disabled_is_a_noop},
        {"packet held until its deadline",   test_packet_is_held_until_its_deadline},
        {"order is preserved",               test_order_is_preserved},
        {"max caps the batch",               test_max_caps_the_batch},
        {"ring full drops and counts",       test_ring_full_drops_and_counts},
        {"head/tail wraparound",             test_wraparound},
        {"drain_all ignores deadlines",      test_drain_all_ignores_deadlines},
    };
    int failures = 0;
    size_t n = sizeof(tests) / sizeof(tests[0]);

    printf("=== wan_delay ring tests ===\n");
    for (size_t i = 0; i < n; i++) {
        int rc = tests[i].fn();
        printf("%s %s\n", rc == 0 ? "  ok  " : "  FAIL", tests[i].name);
        failures += (rc != 0);
    }
    printf("=== %zu passed, %d failed ===\n", n - (size_t)failures, failures);
    return failures != 0;
}
