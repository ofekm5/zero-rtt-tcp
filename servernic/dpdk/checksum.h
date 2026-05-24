#ifndef CHECKSUM_H
#define CHECKSUM_H

#include <rte_ip.h>
#include <rte_tcp.h>

void recalc_ip_checksum(struct rte_ipv4_hdr *ip);
void recalc_tcp_checksum(struct rte_ipv4_hdr *ip, struct rte_tcp_hdr *tcp);

#endif /* CHECKSUM_H */
