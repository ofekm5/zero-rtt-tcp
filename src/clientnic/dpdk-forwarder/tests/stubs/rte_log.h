#ifndef STUB_RTE_LOG_H
#define STUB_RTE_LOG_H

#include <stdio.h>

/* log.h maps LOG_INFO/LOG_WARN/... onto RTE_LOG. Routing them to stderr keeps
 * the module's real logging calls in the compiled path (so a format-string
 * mistake still fails the build) without polluting the test's stdout, which is
 * what the pass/fail lines are read from. */
#define RTE_LOGTYPE_USER1 1

#define RTE_LOG(level, type, ...) fprintf(stderr, __VA_ARGS__)

#endif /* STUB_RTE_LOG_H */
