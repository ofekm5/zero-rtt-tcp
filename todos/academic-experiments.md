Experiments

- Karpathy loop
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
