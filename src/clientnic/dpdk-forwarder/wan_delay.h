#ifndef WAN_DELAY_H
#define WAN_DELAY_H

#include <stdint.h>
#include <rte_mbuf.h>

/* Emulated WAN latency on the ClientNIC↔ServerNIC leg.
 *
 * WHY THIS EXISTS (roadmap.md flaw F2, measurement-methodology-review.md §E):
 * the experiment fakes a long-distance link so the one RTT 0-RTT removes is
 * measurable — the real intra-VPC RTT is ~1.5 ms. That delay used to live in
 * `tc netem` on the Server's egress, which is correct for `send_unlock` and
 * makes an FCT gain impossible: the real SYN-ACK is the packet ServerNIC needs
 * before it can flush buffered client data, so delaying it delays the flush by
 * exactly the modelled RTT.
 *
 * FCT improves only when ServerNIC learns the real ISN *before* the client's
 * data would otherwise have arrived, which holds only if the delay sits on the
 * ClientNIC↔ServerNIC leg. Those ports are DPDK/vfio-pci owned, so `tc` cannot
 * reach them — hence this in-forwarder hold queue. The baseline stack's NIC VMs
 * are kernel-routed and get plain netem on the same leg (endpoint.sh).
 *
 * Model: pure constant delay, no loss/reorder/jitter — matching the netem
 * configuration it replaces (`limit 1000000`, delay only). Because the delay is
 * constant, packets leave in arrival order and a plain FIFO ring is correct; no
 * priority queue is needed.
 *
 * ponytail: fixed-size ring, drop-on-full. A full ring manufactures loss, which
 * is exactly the artifact this module exists to avoid, so drops are counted and
 * logged loudly rather than swallowed. Raise WAN_DELAY_RING if
 * wan_delay_dropped() is ever non-zero.
 */

/* Capacity in packets. Needs to cover offered_pps * delay_seconds. At the
 * measurement profile (LOAD_RATE=2000 conn/s, ~5 packets/flow => ~10k pps) and
 * a 50 ms half-RTT that is ~500 packets, so this is ~16x headroom. Every slot
 * holds an mbuf, so main.c adds WAN_DELAY_RING to the mbuf pool size. */
#define WAN_DELAY_RING 8192

struct wan_delay {
    uint64_t delay_tsc;                     /* 0 = disabled, zero-overhead path */
    uint32_t head;                          /* next write slot */
    uint32_t tail;                          /* next read slot */
    uint64_t dropped;                       /* ring-full drops, must stay 0 */
    uint64_t passed;                        /* packets released to the wire */
    struct rte_mbuf *m[WAN_DELAY_RING];
    uint64_t release[WAN_DELAY_RING];       /* TSC at which m[i] may go out */
};

/* delay_us == 0 disables the queue entirely: wan_delay_enabled() returns 0 and
 * callers keep their original straight-to-TX path. */
void wan_delay_init(struct wan_delay *w, uint32_t delay_us);

static inline int wan_delay_enabled(const struct wan_delay *w)
{
    return w->delay_tsc != 0;
}

static inline uint32_t wan_delay_count(const struct wan_delay *w)
{
    return w->head - w->tail;   /* unsigned wraparound is intentional */
}

/* Take ownership of `m` and hold it for the configured delay.
 * Returns 0 on success; -1 if the ring is full, in which case `m` is freed and
 * the drop counter is incremented. */
int wan_delay_push(struct wan_delay *w, struct rte_mbuf *m);

/* Move up to `max` packets whose release time has passed into `out`.
 * Returns how many were moved; the caller now owns them. */
uint16_t wan_delay_pop_expired(struct wan_delay *w, struct rte_mbuf **out,
                               uint16_t max);

/* Release everything still held, regardless of release time. For shutdown, so
 * in-flight packets are not leaked. */
uint16_t wan_delay_drain_all(struct wan_delay *w, struct rte_mbuf **out,
                             uint16_t max);

#endif /* WAN_DELAY_H */
