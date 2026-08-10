#ifndef STUB_RTE_MBUF_H
#define STUB_RTE_MBUF_H

#include <stdint.h>

/* Opaque stand-in: the WAN hold queue only ever stores and returns the pointer,
 * never dereferences it. */
struct rte_mbuf { int id; };

/* Counts frees so the drop path can be asserted to release rather than leak.
 * Defined in test_wan_delay.c. */
extern uint64_t g_freed;

static inline void rte_pktmbuf_free(struct rte_mbuf *m) { (void)m; g_freed++; }

#endif /* STUB_RTE_MBUF_H */
