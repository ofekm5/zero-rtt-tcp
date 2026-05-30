#ifndef CAPTURE_H
#define CAPTURE_H

#include <rte_mbuf.h>

struct pcap_writer;

int  pcap_writer_open(struct pcap_writer **out, const char *path);
void pcap_writer_write_mbuf(struct pcap_writer *w, const struct rte_mbuf *m);
void pcap_writer_close(struct pcap_writer *w);

#endif /* CAPTURE_H */
