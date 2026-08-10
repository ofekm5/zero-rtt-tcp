---
type: Wiki Entry
title: "React Experiment"
description: "Notes on running and debugging the ReACT DOCA DNS-filtering experiment, including host/DPU counter scripts."
tags: [bluefield, examples, react]
timestamp: 2026-05-23T16:09:41+03:00
---

Source: `infra/bluefield/examples/react/experiment.md`


Optional - Debuging: 
1. On host: /u/dh2156/read_counter.sh
2. On DPU: /home/ubuntu/sources/dh2156/samples/doca_flow/react/read_ovs_counter

Optional - add delay to legitimate responses: 
1. ./delay_dns_responses.sh 100


Run the experiemnts: 
1. On DPU: /home/ubuntu/sources/dh2156/samples/doca_flow/react/react
2. On host: sudo tcpdump -i ens5f0np0 -n -vvv udp src port 53 -w responses_after.pcap
3. On host: sudo tcpdump -i ens5f1np1 -n -vvv udp src port 53 and src host 192.168.5.11 -w responses_before.pcap
4. On host:  sudo tcpreplay -i ens5f0np0 --loop=0 --pps=1000 dns1M.pcap 
5. On host: sudo tcpreplay -i ens5f1np1 --loop=0 --pps=10000 timeout 10 attack.pcap 
6. On host:  python3 compare_pcaps_new.py responses_before.pcap responses_after.pcap