#ifndef FLOW_TABLE_H
#define FLOW_TABLE_H

#include <stdint.h>
#include <string.h>

#define FT_SIZE       1024
#define FT_MAX_BUFFER 64

/* Flow identification: 4-tuple in network byte order */
struct flow_key {
    uint32_t src_ip;
    uint16_t src_port;
    uint32_t dst_ip;
    uint16_t dst_port;
} __attribute__((packed));

/* Buffered packet (raw copy) */
struct pkt_buffer {
    uint8_t *data;
    uint16_t len;
};

/* Per-flow connection state */
struct flow_entry {
    struct flow_key key;
    int             occupied;
    uint32_t        client_isn;          /* host order */
    uint32_t        spoofed_server_isn;  /* host order */
    int             delta_valid;
    uint32_t        seq_delta;           /* host order */
    uint8_t         client_mac[6];
    int             state;               /* 0=SYN_SENT, 1=ESTABLISHED */
    struct pkt_buffer buffer[FT_MAX_BUFFER];
    int             buf_count;
};

/* Hash table */
struct flow_table {
    struct flow_entry entries[FT_SIZE];
};

void              ft_init(struct flow_table *ft);
struct flow_entry *ft_create(struct flow_table *ft, const struct flow_key *key,
                             uint32_t client_isn, uint32_t spoofed_isn,
                             const uint8_t *client_mac);
struct flow_entry *ft_lookup(struct flow_table *ft, const struct flow_key *key);
int               ft_set_delta(struct flow_entry *entry, uint32_t real_server_isn);
int               ft_buffer_pkt(struct flow_entry *entry, const uint8_t *data, uint16_t len);
int               ft_flush_buffer(struct flow_entry *entry, struct pkt_buffer *out, int *count);
void              ft_extract_key(const uint8_t *pkt, struct flow_key *key);
void              ft_reverse_key(const struct flow_key *in, struct flow_key *out);

#endif /* FLOW_TABLE_H */
