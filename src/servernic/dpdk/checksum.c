#include "checksum.h"

void recalc_ip_checksum(struct rte_ipv4_hdr *ip)
{
    ip->hdr_checksum = 0;
    ip->hdr_checksum = rte_ipv4_cksum(ip);
}

void recalc_tcp_checksum(struct rte_ipv4_hdr *ip, struct rte_tcp_hdr *tcp)
{
    tcp->cksum = 0;
    tcp->cksum = rte_ipv4_udptcp_cksum(ip, tcp);
}
