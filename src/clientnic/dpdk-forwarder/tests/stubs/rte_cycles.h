#ifndef STUB_RTE_CYCLES_H
#define STUB_RTE_CYCLES_H

#include <stdint.h>

/* Test-controlled clock, defined in test_wan_delay.c. Tests advance it
 * explicitly instead of sleeping, so the deadline logic is checked exactly
 * rather than approximately. */
extern uint64_t g_fake_tsc;

static inline uint64_t rte_rdtsc(void) { return g_fake_tsc; }

/* 1 MHz => one tick per microsecond, so a test can reason in plain integers:
 * wan_delay_init(&w, 50) becomes a 50-tick hold. */
static inline uint64_t rte_get_tsc_hz(void) { return 1000000ULL; }

#endif /* STUB_RTE_CYCLES_H */
