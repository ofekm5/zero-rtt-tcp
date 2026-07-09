#ifndef LOG_H
#define LOG_H

#include <rte_log.h>

#define RTE_LOGTYPE_FORWARDER RTE_LOGTYPE_USER1

#define LOG_INFO(fmt, ...)  RTE_LOG(INFO,  FORWARDER, fmt "\n", ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)  RTE_LOG(WARNING, FORWARDER, fmt "\n", ##__VA_ARGS__)
#define LOG_ERR(fmt, ...)   RTE_LOG(ERR,   FORWARDER, fmt "\n", ##__VA_ARGS__)
#define LOG_DEBUG(fmt, ...) RTE_LOG(DEBUG, FORWARDER, fmt "\n", ##__VA_ARGS__)

void log_init(void);

#endif /* LOG_H */
