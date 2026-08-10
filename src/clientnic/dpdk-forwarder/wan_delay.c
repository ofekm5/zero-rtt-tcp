#include "wan_delay.h"
#include "log.h"

#include <string.h>
#include <inttypes.h>

#include <rte_cycles.h>

void wan_delay_init(struct wan_delay *w, uint32_t delay_us)
{
    memset(w, 0, sizeof(*w));
    if (delay_us == 0) {
        w->delay_tsc = 0;
        return;
    }
    /* rte_get_tsc_hz() is only valid after EAL init — callers reach this from
     * eth1_init(), which runs well after rte_eal_init(). */
    w->delay_tsc = (rte_get_tsc_hz() / 1000000ULL) * (uint64_t)delay_us;
    LOG_INFO("wan-delay: holding middle-leg TX for %u us (%" PRIu64
             " cycles, ring=%u packets)",
             delay_us, w->delay_tsc, WAN_DELAY_RING);
}

int wan_delay_push(struct wan_delay *w, struct rte_mbuf *m)
{
    if (wan_delay_count(w) >= WAN_DELAY_RING) {
        /* Dropping here manufactures exactly the packet loss this module is
         * supposed to be free of, so it must never be silent. */
        w->dropped++;
        rte_pktmbuf_free(m);
        return -1;
    }
    uint32_t slot = w->head & (WAN_DELAY_RING - 1);
    w->m[slot]       = m;
    w->release[slot] = rte_rdtsc() + w->delay_tsc;
    w->head++;
    return 0;
}

uint16_t wan_delay_pop_expired(struct wan_delay *w, struct rte_mbuf **out,
                               uint16_t max)
{
    uint64_t now = rte_rdtsc();
    uint16_t n = 0;

    /* Constant delay => release times are non-decreasing along the ring, so the
     * first unexpired entry ends the scan. */
    while (n < max && wan_delay_count(w) > 0) {
        uint32_t slot = w->tail & (WAN_DELAY_RING - 1);
        if (w->release[slot] > now)
            break;
        out[n++] = w->m[slot];
        w->tail++;
    }
    w->passed += n;
    return n;
}

uint16_t wan_delay_drain_all(struct wan_delay *w, struct rte_mbuf **out,
                             uint16_t max)
{
    uint16_t n = 0;
    while (n < max && wan_delay_count(w) > 0) {
        uint32_t slot = w->tail & (WAN_DELAY_RING - 1);
        out[n++] = w->m[slot];
        w->tail++;
    }
    return n;
}
