# Dockerfile for wire-example DPDK application
# Build on ARM64 architecture for Bluefield DPU

FROM nvcr.io/nvidia/doca/doca:2.9.3-devel

WORKDIR /app

# Copy source code
COPY wire.c .

# Build the application using the same flags as build.sh
RUN gcc wire.c -o wire \
    -I/opt/mellanox/dpdk/include/aarch64-linux-gnu/dpdk \
    -I/opt/mellanox/dpdk/include/dpdk \
    -I/opt/mellanox/doca/include/ \
    -L/opt/mellanox/dpdk/lib/aarch64-linux-gnu \
    -lrte_eal -lrte_mempool -lrte_ring -lrte_ethdev -lrte_mbuf \
    -lstdc++ -libverbs -lmlx5 \
    && chmod +x wire \
    && rm wire.c

# Set up environment
ENV RTE_SDK=/opt/mellanox/dpdk
ENV LD_LIBRARY_PATH=/opt/mellanox/dpdk/lib/aarch64-linux-gnu:/opt/mellanox/doca/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH}

# Default command - show help (list ports)
# Users can override with: docker run wire-app -l 0-2 -- 2 3
ENTRYPOINT ["/app/wire"]
CMD []

# Labels for documentation
LABEL maintainer="Bluefield DPU Team"
LABEL description="Wire-example: Bidirectional packet forwarding between DPDK ports"
LABEL version="1.0"
