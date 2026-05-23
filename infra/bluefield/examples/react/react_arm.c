
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>  // for usleep()

#include <rte_ethdev.h>
#include <rte_ip.h>
#include <rte_tcp.h>
#include <rte_udp.h>
#include <signal.h>


#include <doca_log.h>
#include <doca_flow.h>

#include "flow_common.h"
#include "react.h"

DOCA_LOG_REGISTER(REACT);

bool force_quit = false;


/**
 * Signal handler for graceful termination.
 *
 * @param signum Signal number received (e.g., SIGINT or SIGTERM)
 */
void
signal_handler(int signum)
{
	if (signum == SIGINT || signum == SIGTERM) {
		DOCA_LOG_INFO("Signal %d received, preparing to exit", signum);
		global_force_quit = true;
	}
}

/**
 * Flush all RX queues for a specific DPDK port.
 *
 * @param port_id [in] The ID of the port whose queues will be flushed.
 */
void
flush_queues(int port_id)
{
	struct rte_mbuf *packets[PACKET_BURST];
        int nb_packets = 0;
        for (int queue_id=0; queue_id < 16; queue_id++) {
        	while(1)
	        {
            		nb_packets = rte_eth_rx_burst(port_id, queue_id, packets, PACKET_BURST);
             		if(nb_packets<=0)
                		break;
		}
        }
}


/** *
 * Waits until rx_q[i] changes twice (i.e., sees three distinct values).
 * Assumes port_id is valid and i < RTE_ETHDEV_QUEUE_STAT_CNTRS.
 * 
 * @param port_id [in] The ID of the port to monitor.
 * @param queue_index [in] The index of the RX queue to monitor.
 * @param poll_interval_us [in] The interval in microseconds to wait between polls.
 */
void wait_for_rx_qi_changes(uint16_t port_id, uint16_t queue_index, uint64_t poll_interval_us) {
    struct rte_eth_stats stats;
    uint64_t last = 0, prev = 0;
    int change_count = 0;

    if (rte_eth_stats_get(port_id, &stats) != 0) {
        DOCA_LOG_INFO("Failed to get stats for port %u", port_id);
        return;
    }

    prev = stats.q_ipackets[queue_index];

    while (change_count < 2 && !global_force_quit) {
        usleep(poll_interval_us);

        if (rte_eth_stats_get(port_id, &stats) != 0) {
            DOCA_LOG_INFO("Failed to get stats for port %u", port_id);
            return;
        }

        last = stats.q_ipackets[queue_index];

        if (last != prev) {
            change_count++;
            prev = last;
        }
    }
}

/**
 * Dequeue packets from DPDK queues and process DNS keys using ReAct's Bloom filters.
 *
 * @param args [in] A pointer to worker_params struct including queue index, phase, and Bloom filters.
 * @return Always returns 0.
 */
int
process_packets(void *args)
{
	struct rte_mbuf *packets[PACKET_BURST];
    int queue_index =((worker_params *)args)->queue_index;
    int *phase =((worker_params *)args)->phase;
    bloom_filter_t **bfs = ((worker_params *)args)->bfs;
    bool *within_burst = ((worker_params *)args)->within_burst;
    bloom_type_t type = bfs[0]->type;

	int nb_packets = 0;
 	int i;
    struct rte_mbuf *tx_bufs[TX_BURST];
    uint16_t tx_count = 0;
    uint64_t last_flush_tsc = rte_get_tsc_cycles();

    
    enum burst_direction burst_type;

    while(!force_quit)
    {
        *within_burst = false;
        burst_type = OUTGOING_REQUESTS;
        nb_packets = rte_eth_rx_burst(burst_type, queue_index, packets, PACKET_BURST);
        if(nb_packets<=0) {
            burst_type = INCOMING_RESPONSES;
            nb_packets = rte_eth_rx_burst(burst_type, queue_index, packets, PACKET_BURST);
            if(nb_packets<=0)  {
                continue;
            }
        }
        *within_burst = true;
        uint64_t now = rte_get_tsc_cycles();

        /* Bloom filters are precomputed for the entire burst */
        bloom_filter_t *bf_add = bfs[*phase];
        bloom_filter_t *bf_check = bf_add; 
        uint64_t *bf_check_array; 

        if (bf_add == NULL) {
            DOCA_LOG_ERR("Uninitialized Bloom filter;  lcore %d, phase %d", rte_lcore_id(), *phase);
            for (i = 0; i < nb_packets; i++) {
                rte_pktmbuf_free(packets[i]);
            }
            continue;
        }
        else if (type == BLOOM_THREAD_SAFE && bf_add->bit_array_ts == NULL) {
            DOCA_LOG_ERR("Uninitialized bit array; lcore %d, phase %d", rte_lcore_id(), *phase);
                for (i = 0; i < nb_packets; i++) {
                    rte_pktmbuf_free(packets[i]);
                }
            continue;
        }
        else if (type == BLOOM_CLASSIC && bf_add->bit_array == NULL) 
        {
            DOCA_LOG_ERR("Uninitialized bit array;  lcore %d, phase %d", rte_lcore_id(), *phase);
            for (i = 0; i < nb_packets; i++) {
                rte_pktmbuf_free(packets[i]);
            }
            continue;
        }
        else if (type == BLOOM_COUNTING && bf_add->count_array == NULL) {
            DOCA_LOG_ERR("Uninitialized bit array;  lcore %d, phase %d", rte_lcore_id(), *phase);
            for (i = 0; i < nb_packets; i++) {
                rte_pktmbuf_free(packets[i]);
            }
            continue;
        }

        if(type == BLOOM_CLASSIC || type == BLOOM_THREAD_SAFE) {
            bf_check = bfs[(*phase+2)%3];
        } 
        
        if (bf_check == NULL) {
            DOCA_LOG_ERR("Uninitialized Bloom filter;  lcore %d, phase %d", rte_lcore_id(), *phase);
            for (i = 0; i < nb_packets; i++) {
                rte_pktmbuf_free(packets[i]);
            }
            continue;
        }
        else if (type == BLOOM_THREAD_SAFE)
        {
            if( bf_check->bit_array_ts == NULL) {
                DOCA_LOG_ERR("Uninitialized bit array; lcore %d, phase %d", rte_lcore_id(), *phase);
                for (i = 0; i < nb_packets; i++) {
                    rte_pktmbuf_free(packets[i]);
                }
                continue;
            }
            else {
                bf_check_array = (uint64_t *)bf_check->bit_array_ts;
            }
        }
        else if (type == BLOOM_CLASSIC)
        {   
            if(bf_check->bit_array == NULL) {
                DOCA_LOG_ERR("Uninitialized bit array;  lcore %d, phase %d", rte_lcore_id(), *phase);
                for (i = 0; i < nb_packets; i++) {
                    rte_pktmbuf_free(packets[i]);
                }
                continue;
            }
            else {
                bf_check_array = (uint64_t *)bf_check->bit_array;
            }
        }

        /* Per Packet Loop we want to optimize */
        for (i = 0; i < nb_packets; i++) {
            struct rte_mbuf *pkt = packets[i];
            struct rte_ether_hdr *eth_hdr = rte_pktmbuf_mtod(pkt, struct rte_ether_hdr *);
            struct rte_ipv4_hdr *ipv4_hdr;
            uint8_t key[12] = {0};  // 4+4+2+2 = 12 bytes

            // Check if packet is IPv4
            if (RTE_BE16(eth_hdr->ether_type) != RTE_ETHER_TYPE_IPV4) 
                continue;
            ipv4_hdr = (struct rte_ipv4_hdr *)(eth_hdr + 1);
            uint8_t proto = ipv4_hdr->next_proto_id;
            if (proto != IPPROTO_UDP) 
                continue;

            struct rte_udp_hdr *udp_hdr = (struct rte_udp_hdr *)((unsigned char *)ipv4_hdr + (ipv4_hdr->ihl * 4));
            uint8_t *dns_hdr = ((uint8_t *)udp_hdr) + sizeof(struct rte_udp_hdr);        
            memcpy(&key[0], &ipv4_hdr->src_addr, 4);       // source IP
            memcpy(&key[4], &ipv4_hdr->dst_addr, 4);       // destination IP
            memcpy(&key[8], &udp_hdr->dst_port, 2);        // client port (destination UDP port)
            memcpy(&key[10], dns_hdr, 2);                  // DNS transaction ID
            
            if (burst_type == OUTGOING_REQUESTS) 
            {
                bloom_add(bf_add,key,12);
                rte_pktmbuf_free(pkt);
            }
            else  
            {   
                // INCOMING_RESPONSES
                uint32_t h1, h2;
                bloom_get_indices(key,  12, bf_add->size, &h1, &h2);
            
                if(bloom_check_with_indices(bf_add,h1,h2)) 
                {
                    tx_bufs[tx_count++] = pkt;

                     if (tx_count == TX_BURST) {
                        rte_eth_tx_burst(OUTGOING_REQUESTS, queue_index, tx_bufs, tx_count);
                        tx_count = 0;
                        last_flush_tsc = now;
                    }
                    //rte_eth_tx_burst(OUTGOING_REQUESTS, queue_index, &pkt, 1);
                }
                else if( (type==BLOOM_CLASSIC || type==BLOOM_THREAD_SAFE) && bloom_check_bit_array(bf_check_array,h1,h2))
                {
                    tx_bufs[tx_count++] = pkt;

                     if (tx_count == TX_BURST) {
                        rte_eth_tx_burst(OUTGOING_REQUESTS, queue_index, tx_bufs, tx_count);
                        tx_count = 0;
                        last_flush_tsc = now;
                    }
                    //rte_eth_tx_burst(OUTGOING_REQUESTS, queue_index, &pkt, 1);
                }
                else
                {
                    rte_pktmbuf_free(pkt); // dropped, one BF for counting, two for classic/thread-safe
                } 

            }
        }
        if (tx_count > 0 && (now - last_flush_tsc > FLUSH_INTERVAL_CYCLES)) {
            rte_eth_tx_burst(OUTGOING_REQUESTS, queue_index, tx_bufs, tx_count);
            tx_count = 0;
            last_flush_tsc = now;
        }
    }

	return 0;
}
