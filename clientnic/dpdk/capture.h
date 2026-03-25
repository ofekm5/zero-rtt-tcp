#ifndef CAPTURE_H
#define CAPTURE_H

#include <rte_mbuf.h>

/*
 * Minimal pcap writer for DPDK mbufs.
 *
 * Writes a valid pcap file (LINKTYPE_ETHERNET, microsecond timestamps) that
 * validate_0rtt_capture.py can read as the server-side (eth1) capture.
 *
 * Usage:
 *   struct pcap_writer *cap;
 *   pcap_writer_open(&cap, "/tmp/server_side.pcap");
 *   ...
 *   pcap_writer_write_mbuf(cap, mbuf);   // call for each eth1 RX packet
 *   ...
 *   pcap_writer_close(cap);
 */

struct pcap_writer;

/* Open a new pcap file for writing. Returns 0 on success, -1 on error. */
int  pcap_writer_open(struct pcap_writer **out, const char *path);

/* Append one mbuf (must be a single contiguous segment) to the file. */
void pcap_writer_write_mbuf(struct pcap_writer *w, const struct rte_mbuf *m);

/* Flush and close the file. */
void pcap_writer_close(struct pcap_writer *w);

#endif /* CAPTURE_H */
