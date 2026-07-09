#include "capture.h"
#include "log.h"

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>

#include <rte_mbuf.h>

#define PCAP_MAGIC      0xa1b2c3d4u
#define PCAP_VERSION_MAJ 2
#define PCAP_VERSION_MIN 4
#define PCAP_SNAPLEN    65535
#define PCAP_LINKTYPE_ETHERNET 1

struct pcap_file_hdr {
    uint32_t magic;
    uint16_t version_major;
    uint16_t version_minor;
    int32_t  thiszone;
    uint32_t sigfigs;
    uint32_t snaplen;
    uint32_t network;
} __attribute__((packed));

struct pcap_pkt_hdr {
    uint32_t ts_sec;
    uint32_t ts_usec;
    uint32_t incl_len;
    uint32_t orig_len;
} __attribute__((packed));

struct pcap_writer {
    FILE *fp;
};

int pcap_writer_open(struct pcap_writer **out, const char *path)
{
    struct pcap_writer *w = calloc(1, sizeof(*w));
    if (!w)
        return -1;

    w->fp = fopen(path, "wb");
    if (!w->fp) {
        LOG_ERR("capture: cannot open %s", path);
        free(w);
        return -1;
    }

    struct pcap_file_hdr hdr = {
        .magic         = PCAP_MAGIC,
        .version_major = PCAP_VERSION_MAJ,
        .version_minor = PCAP_VERSION_MIN,
        .thiszone      = 0,
        .sigfigs       = 0,
        .snaplen       = PCAP_SNAPLEN,
        .network       = PCAP_LINKTYPE_ETHERNET,
    };

    if (fwrite(&hdr, sizeof(hdr), 1, w->fp) != 1) {
        LOG_ERR("capture: failed to write pcap header");
        fclose(w->fp);
        free(w);
        return -1;
    }

    fflush(w->fp);
    LOG_INFO("capture: writing eth1 packets to %s", path);
    *out = w;
    return 0;
}

void pcap_writer_write_mbuf(struct pcap_writer *w, const struct rte_mbuf *m)
{
    if (!w || !w->fp)
        return;

    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);

    uint32_t pkt_len = rte_pktmbuf_data_len(m);
    uint32_t caplen  = pkt_len < PCAP_SNAPLEN ? pkt_len : PCAP_SNAPLEN;

    struct pcap_pkt_hdr phdr = {
        .ts_sec   = (uint32_t)ts.tv_sec,
        .ts_usec  = (uint32_t)(ts.tv_nsec / 1000),
        .incl_len = caplen,
        .orig_len = pkt_len,
    };

    fwrite(&phdr, sizeof(phdr), 1, w->fp);
    fwrite(rte_pktmbuf_mtod(m, const void *), caplen, 1, w->fp);
}

void pcap_writer_close(struct pcap_writer *w)
{
    if (!w)
        return;
    if (w->fp) {
        fflush(w->fp);
        fclose(w->fp);
    }
    free(w);
    LOG_INFO("capture: pcap file closed");
}
