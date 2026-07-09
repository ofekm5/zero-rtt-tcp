#include "log.h"

RTE_LOG_REGISTER_DEFAULT(forwarder_logtype, INFO);

void log_init(void)
{
    rte_log_set_level(RTE_LOGTYPE_FORWARDER, RTE_LOG_INFO);
}
