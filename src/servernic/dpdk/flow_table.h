#ifndef FLOW_TABLE_H
#define FLOW_TABLE_H

#include <stdint.h>
#include <string.h>

/* Open-addressing table (mask = FT_SIZE-1, must stay a power of two). Sized to
 * hold the 100k-connection benchmark at a ~0.4 load factor so linear-probe
 * chains on the per-packet lookup path stay short. The entries[] array is BSS
 * and lazily committed, so only touched flows consume RAM. */
#define FT_SIZE       262144
#define FT_MAX_BUFFER 64

#define FLOW_STATE_PENDING 0
#define FLOW_STATE_ACTIVE  1

/* Flow identification: 4-tuple in network byte order (client→server direction) */
struct flow_key {
    uint32_t src_ip;
    uint16_t src_port;
    uint32_t dst_ip;
    uint16_t dst_port;
} __attribute__((packed));

/* Buffered packet awaiting delta computation */
struct pkt_buffer {
    uint8_t *data;
    uint16_t len;
};

/* Per-flow connection state (ServerNIC is the sole translator under T8) */
struct flow_entry {
    struct flow_key key;
    int             occupied;
    uint32_t        spoofed_server_isn; /* V, host order — from SYN ack-num field */
    uint32_t        real_server_isn;    /* host order — from real SYN-ACK */
    uint32_t        seq_delta;          /* (V - real_isn) & 0xFFFFFFFF, host order */
    int             delta_valid;
    int             state;              /* FLOW_STATE_PENDING or FLOW_STATE_ACTIVE */
    uint8_t         server_mac[6];      /* Server-side next-hop MAC for eth2 TX */
    struct pkt_buffer buffer[FT_MAX_BUFFER];
    int             buf_count;
    uint64_t        t0_tsc;             /* TSC at SYN ingress on eth1 (TTFB start) */
    int             ttfb_logged;        /* 1 once first s2c data byte was timed */
};

/* Hash table */
struct flow_table {
    struct flow_entry entries[FT_SIZE];
};

void              ft_init(struct flow_table *ft);
struct flow_entry *ft_create(struct flow_table *ft, const struct flow_key *key,
                             uint32_t spoofed_isn, const uint8_t *server_mac);
struct flow_entry *ft_lookup(struct flow_table *ft, const struct flow_key *key);
int               ft_set_delta(struct flow_entry *entry, uint32_t real_server_isn);
int               ft_buffer_pkt(struct flow_entry *entry, const uint8_t *data, uint16_t len);
int               ft_flush_buffer(struct flow_entry *entry, struct pkt_buffer *out, int *count);
void              ft_extract_key(const uint8_t *pkt, struct flow_key *key);
void              ft_reverse_key(const struct flow_key *in, struct flow_key *out);

#endif /* FLOW_TABLE_H */
