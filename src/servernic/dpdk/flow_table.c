#include "flow_table.h"

#include <stdlib.h>
#include <stdio.h>
#include <arpa/inet.h>
#include <rte_cycles.h>

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
                             uint32_t spoofed_isn, const uint8_t *server_mac)
{
    uint32_t idx = hash_key(key);
    for (uint32_t i = 0; i < FT_SIZE; i++) {
        uint32_t slot = (idx + i) & (FT_SIZE - 1);
        struct flow_entry *e = &ft->entries[slot];
        if (!e->occupied) {
            e->occupied          = 1;
            e->key               = *key;
            e->spoofed_server_isn = spoofed_isn;
            e->real_server_isn   = 0;
            e->seq_delta         = 0;
            e->delta_valid       = 0;
            e->state             = FLOW_STATE_PENDING;
            e->buf_count         = 0;
            e->t0_tsc            = rte_rdtsc(); /* TTFB start: SYN ingress */
            e->ttfb_logged       = 0;
            memcpy(e->server_mac, server_mac, 6);
            return e;
        }
        if (keys_equal(&e->key, key)) {
            return e; /* already exists — idempotent for retransmitted SYN */
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

int ft_set_delta(struct flow_entry *entry, uint32_t real_server_isn)
{
    if (entry->delta_valid)
        return 0; /* idempotent for duplicate SYN-ACKs */
    entry->real_server_isn = real_server_isn;
    entry->seq_delta       = (entry->spoofed_server_isn - real_server_isn) & 0xFFFFFFFF;
    entry->delta_valid     = 1;
    entry->state           = FLOW_STATE_ACTIVE;
    return 1;
}

int ft_buffer_pkt(struct flow_table *ft, struct flow_entry *entry,
                  const uint8_t *data, uint16_t len)
{
    if (entry->buf_count >= FT_MAX_BUFFER)
        return -1; /* per-flow buffer overflow */
    if (ft->buffered_bytes + len > FT_MAX_BUFFERED_BYTES)
        return -2; /* global ceiling — shed rather than risk OOM (capacity-model §7) */
    uint8_t *copy = malloc(len);
    if (!copy)
        return -1;
    memcpy(copy, data, len);
    entry->buffer[entry->buf_count].data = copy;
    entry->buffer[entry->buf_count].len  = len;
    entry->buf_count++;
    ft->buffered_bytes += len;
    return 0;
}

int ft_flush_buffer(struct flow_table *ft, struct flow_entry *entry,
                    struct pkt_buffer *out, int *count)
{
    *count = entry->buf_count;
    uint64_t freed_bytes = 0;
    for (int i = 0; i < entry->buf_count; i++) {
        out[i] = entry->buffer[i];
        freed_bytes += entry->buffer[i].len;
    }
    entry->buf_count = 0;
    ft->buffered_bytes -= (freed_bytes < ft->buffered_bytes) ? freed_bytes : ft->buffered_bytes;
    return 0;
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
