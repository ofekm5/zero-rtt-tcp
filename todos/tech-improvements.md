Tech Improvements

- ISN passing from ClientNIC to ServerNIC (piggybacked in-between or compressed into SYN)
- Shift sequence number translation responsibility between sides
- BlueField-3 architecture: eSwitch for translation, DPA for connection setup and ISN generation, ARM core for DPDK setup
- RSS-based flow sharding
- Buffer ingress packets before handshake completes
- Explore using Corundum: https://github.com/corundum/corundum

Papers to read:
- https://www.usenix.org/conference/osdi23/presentation/wei-smartnic
- https://arxiv.org/html/2509.21656
- https://www.diva-portal.org/smash/get/diva2:1676162/FULLTEXT01.pdf
- https://www.cs.rice.edu/~eugeneng/papers/SIGCOMM23-Pipeleon.pdf
