#ifndef FLOW_TABLE_H
#define FLOW_TABLE_H

#include <stdint.h>
#include <string.h>

#define FT_SIZE 1024

/* Flow identification: 4-tuple in network byte order */
struct flow_key {
    uint32_t src_ip;
    uint16_t src_port;
    uint32_t dst_ip;
    uint16_t dst_port;
} __attribute__((packed));

/* Per-flow connection state (slim: no delta, no buffer — ServerNIC owns those) */
struct flow_entry {
    struct flow_key key;
    int             occupied;
    uint32_t        spoofed_server_isn;  /* V, host order */
    uint8_t         client_mac[6];
    int             state;               /* 0=SYN_SENT, 1=ESTABLISHED */
};

/* Hash table */
struct flow_table {
    struct flow_entry entries[FT_SIZE];
};

void              ft_init(struct flow_table *ft);
struct flow_entry *ft_create(struct flow_table *ft, const struct flow_key *key,
                             uint32_t spoofed_isn, const uint8_t *client_mac);
struct flow_entry *ft_lookup(struct flow_table *ft, const struct flow_key *key);
void              ft_extract_key(const uint8_t *pkt, struct flow_key *key);
void              ft_reverse_key(const struct flow_key *in, struct flow_key *out);

#endif /* FLOW_TABLE_H */
