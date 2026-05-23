#ifndef REACT__H_
#define REACT__H_

#include <doca_argp.h>
#include <doca_flow.h>
#include <doca_log.h>
#include "flow_common.h"

#define PACKET_BURST 64	/* The number of packets in the rx queue read together */
#define TX_BURST 32 /* The number of packets in the tx queue sent together */
#define FLUSH_INTERVAL_CYCLES (rte_get_timer_hz() / 20000) // 50 µs

//#define HEAD_PACKET_BURST 10

// --- Bloom filter types ---
typedef enum {
   BLOOM_CLASSIC,
   BLOOM_COUNTING,
   BLOOM_THREAD_SAFE
} bloom_type_t;

// --- Bloom filter struct ---
typedef struct {
   bloom_type_t type;
   size_t size;          // Number of elements (CLASSIC: bits, COUNTING: bytes)
   union {
       uint64_t *bit_array;     // For CLASSIC
       uint8_t *count_array;      // For COUNTING
       _Atomic uint64_t *bit_array_ts;     // For THREAD_SAFE
   };
} bloom_filter_t;

typedef struct {
	 int ingress_port;
	 int queue_index;
    bloom_filter_t **bfs;
    int *phase; /* 0, 1, or 2 */
    int *nb_requests; // not used
    int *nb_responses_fwd; // not used
    int *nb_responses_dropped; // not used
	 double measurment_len; // not used
	 double measurment_freq; // not used
    bool *within_burst;
 } worker_params;

 /* ReAct application configuration */
struct react_config {
   struct application_dpdk_config *dpdk_cfg;       /* DPDK configurations */
   size_t bloom_size;                             
   uint16_t bloom_swap_interval;
   bloom_type_t bloom_type; 
   uint16_t nb_cores;
   uint16_t timeout;
};

extern bool force_quit;
extern bool global_force_quit;

enum burst_direction { INCOMING_RESPONSES = 0, OUTGOING_REQUESTS = 1 };



/* Signal handler to stop the apps on the arm cores*/
void signal_handler(int signum);

/* Functions that can be run on the arm core */
int process_packets(void *args);

/* Block until we know progress made by the ARM core and it is safe to move on */
void wait_for_rx_qi_changes(uint16_t port_id, uint16_t queue_index, uint64_t poll_interval_us);

/* Pipes and entries paramertized creations */
doca_error_t create_react_pipe(struct doca_flow_port *port, 
                               struct doca_flow_pipe **pipe, 
                               int nb_queues, 
                               enum burst_direction direction); //OUTGOING_REQUESTS or  INCOMING_RESPONSES
                               

doca_error_t create_spraying_pipe(struct doca_flow_port *port, 
                                struct doca_flow_pipe **pipe, 
                                int nb_queues); 
                                
doca_error_t create_copy_to_meta_pipe(struct doca_flow_port *port, 
                                      struct doca_flow_pipe **pipe, 
                                      struct doca_flow_pipe *next_pipe,
                                      int direction); 



/* ReAct's Logic */
doca_error_t flow_react(int dpdk_queues, struct react_config);
                   

/* Bloom Filter methods*/
bloom_filter_t *bloom_init(size_t size_bits, bloom_type_t type);
void bloom_free(bloom_filter_t *bf);
uint32_t djb2(uint8_t *str, int len);
uint32_t sdbm(uint8_t *str, int len);
void bloom_add(bloom_filter_t *bf,  uint8_t *key, int len);
int bloom_check(bloom_filter_t *bf, uint8_t *key, int len);

int bloom_check_with_indices(bloom_filter_t *bf, uint32_t h1, uint32_t h2);
int bloom_check_bit_array(__uint64_t *bit_array, uint32_t h1, uint32_t h2);

/**
 * Get two indices for a Bloom filter based on the key. 
 * 
 * @param key Pointer to the key data.
 * @param len Length of the key data.
 * @param bloom_size Size of the Bloom filter.
 * @param index1 Pointer to store the first index.
 * @param index2 Pointer to store the second index.
 */
static inline void bloom_get_indices(const uint8_t *key, size_t len, uint32_t bloom_size,
   uint32_t *index1, uint32_t *index2) 
{
   uint32_t h1 = 5381;
   uint32_t h2 = 0;

   for (size_t i = 0; i < len; ++i) {
      h1 = ((h1 << 5) + h1) + key[i];                // djb2
      h2 = key[i] + (h2 << 6) + (h2 << 16) - h2;     // sdbm
   }

   *index1 = h1 % bloom_size;
   *index2 = (h1 + h2) % bloom_size;
}


 #endif


