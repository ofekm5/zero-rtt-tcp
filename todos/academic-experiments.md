Experiments

- QUIC testbed — reference: https://chatgpt.com/share/69efb1eb-e984-83eb-bda0-a9e6df2a9d81
- Prepare testbeds for BF3 and AWS
- Define key metrics: FCT, throughput, TTFB
- Add a baseline for each scenario — both classic TCP and QUIC
- Add more parallel streams — find the threshold where throughput degrades significantly
- Cross-region testing under higher latency conditions
- Start on smaller testbeds, then use `tc` (traffic control) to simulate latency
- TRex vs iperf — compare traffic generators for stress testing
- Address the research hypothesis
- Reference: https://github.com/RC4ML/BenchBF3

Papers to read:
- https://www.usenix.org/conference/osdi23/presentation/wei-smartnic
- https://arxiv.org/html/2509.21656
- https://www.diva-portal.org/smash/get/diva2:1676162/FULLTEXT01.pdf
- https://www.cs.rice.edu/~eugeneng/papers/SIGCOMM23-Pipeleon.pdf
