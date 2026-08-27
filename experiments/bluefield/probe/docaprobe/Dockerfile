FROM nvcr.io/nvidia/doca/doca:2.9.3-devel

# Set working directory to DOCA applications directory
WORKDIR /opt/mellanox/doca/applications

# Copy probe source (build context is docaprobe/)
COPY . /tmp/eswitch_probe/

# Build with meson/ninja, shipped inside this devel image
RUN cd /tmp/eswitch_probe && \
    meson /tmp/build && \
    ninja -C /tmp/build

# Copy the built binary to a runtime directory
RUN mkdir -p /runtime && \
    cp /tmp/build/eswitch_probe /runtime/eswitch_probe

WORKDIR /runtime

# Rule parameters (5-tuple, delta, direction, egress port) are passed as
# CLI args at `docker run` time so syntax is iterated by re-running the
# loaded image rather than rebuilding it (design.md "What Changes").
ENTRYPOINT ["/runtime/eswitch_probe"]
