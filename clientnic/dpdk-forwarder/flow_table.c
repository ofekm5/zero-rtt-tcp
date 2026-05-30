#include "flow_table.h"

#include <stdlib.h>
#include <stdio.h>
#include <arpa/inet.h>

static uint32_t hash_key(const struct flow_key *key)
{
    uint32_t h = key->src_ip ^ key->dst_ip;
    h ^= ((uint32_t)key->src_port << 16) | key->dst_port;
    h ^= h >> 16;
    h *= 0x45d9f3b;
    h ^= h >> 16;
    return h & (FT_SIZE - 1);
}

static int keys_equal(const struct flow_key *a, const struct flow_key *b)
{
    return a->src_ip   == b->src_ip   &&
           a->dst_ip   == b->dst_ip   &&
           a->src_port == b->src_port &&
           a->dst_port == b->dst_port;
}

void ft_init(struct flow_table *ft)
{
    memset(ft, 0, sizeof(*ft));
}

struct flow_entry *ft_create(struct flow_table *ft, const struct flow_key *key,
                             uint32_t spoofed_isn, const uint8_t *client_mac)
{
    uint32_t idx = hash_key(key);
    for (uint32_t i = 0; i < FT_SIZE; i++) {
        uint32_t slot = (idx + i) & (FT_SIZE - 1);
        struct flow_entry *e = &ft->entries[slot];
        if (!e->occupied) {
            e->occupied          = 1;
            e->key               = *key;
            e->spoofed_server_isn = spoofed_isn;
            e->state             = 0; /* SYN_SENT */
            memcpy(e->client_mac, client_mac, 6);
            return e;
        }
        if (keys_equal(&e->key, key)) {
            return e; /* already exists */
        }
    }
    return NULL; /* table full */
}

struct flow_entry *ft_lookup(struct flow_table *ft, const struct flow_key *key)
{
    uint32_t idx = hash_key(key);
    for (uint32_t i = 0; i < FT_SIZE; i++) {
        uint32_t slot = (idx + i) & (FT_SIZE - 1);
        struct flow_entry *e = &ft->entries[slot];
        if (!e->occupied)
            return NULL;
        if (keys_equal(&e->key, key))
            return e;
    }
    return NULL;
}

void ft_extract_key(const uint8_t *pkt, struct flow_key *key)
{
    const uint8_t *ip  = pkt;
    const uint8_t *tcp = ip + ((ip[0] & 0x0F) * 4);

    memcpy(&key->src_ip, ip + 12, 4);
    memcpy(&key->dst_ip, ip + 16, 4);
    memcpy(&key->src_port, tcp + 0, 2);
    memcpy(&key->dst_port, tcp + 2, 2);
}

void ft_reverse_key(const struct flow_key *in, struct flow_key *out)
{
    out->src_ip   = in->dst_ip;
    out->src_port = in->dst_port;
    out->dst_ip   = in->src_ip;
    out->dst_port = in->src_port;
}
