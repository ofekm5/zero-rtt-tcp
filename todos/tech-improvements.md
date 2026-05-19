Tech Improvements

- ISN passing from ClientNIC to ServerNIC (piggybacked in-between or compressed into SYN)
- Shift sequence number translation responsibility between sides
- BlueField-3 architecture: eSwitch for translation, DPA for connection setup and ISN generation, ARM core for DPDK setup
- RSS-based flow sharding
- Buffer ingress packets before handshake completes
- Explore using Corundum: https://github.com/corundum/corundum
- QUIC-style Connection ID for fast routing — widen the ISN-passing channel (T3 or T6 from `generated-isn-compression-options.md`; T8's 4 bytes are too narrow) to carry a structured CID `{version, backend_id, tenant_id, flow_nonce, auth_tag}` instead of just `V`. Enables: stateless ServerNIC routing by CID lookup, multi-backend fan-out via CID-encoded backend hint, connection survival across client NAT rebind.
  - Only worth implementing when fan-out > 1 (multiple ServerNICs or backend pools) or multi-tenant routing becomes a requirement. For the current single-ClientNIC / single-ServerNIC topology, plain `V` via T3 or T8 is sufficient.