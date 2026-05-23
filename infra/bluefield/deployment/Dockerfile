FROM nvcr.io/nvidia/doca/doca:2.9.3-devel

# Set working directory to DOCA applications directory
WORKDIR /opt/mellanox/doca/applications

# Copy application source code (build context is already src/)
COPY . /tmp/inspect_syn_vnf/

# Build the application using our standalone meson configuration
# We build directly from the src/ directory with our custom meson files
RUN cd /tmp/inspect_syn_vnf && \
    meson /tmp/build && \
    ninja -C /tmp/build

# Create runtime directory and copy the built binary
RUN mkdir -p /runtime && \
    cp /tmp/build/doca_inspect_syn_vnf /runtime/doca_inspect_syn_vnf

# Set working directory to runtime
WORKDIR /runtime

# Create a startup script with your exact command line arguments
RUN echo '#!/bin/bash\n\
echo "Starting InspectSynVnf with optimized configuration..."\n\
echo "Using only mlx5_core.sf.2 for ingress (no egress subfunction needed)"\n\
echo "Configuration: rx-only, 2 queues, stats timer 2 seconds"\n\
echo ""\n\
exec ./doca_inspect_syn_vnf \\\n\
  -l 0-1 -n 4 \\\n\
  -a auxiliary:mlx5_core.sf.2,dv_flow_en=2 \\\n\
  -- --rx-only --nr-queues 2 --stats-timer 2\n\
' > /runtime/start.sh && chmod +x /runtime/start.sh

# Set the startup script as the default command
CMD ["/runtime/start.sh"]