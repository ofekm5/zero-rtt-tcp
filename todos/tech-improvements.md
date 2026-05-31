Tech Improvements

## [URGENT] RUNS3 BlueField BFB Reinstall {#runs3-bluefield-reinstall}
**Problem:** BlueField DPU is offline for unknown reason. Need to reinstall its BFB (BlueField firmware image).

**Solution:**
1. Use `/runs-lab-connect` to connect to the gateway
2. From gateway, connect to BF BMC at 10.13.36.233
3. Maintain persistent connection to gateway for multi-terminal access during reinstall process
4. Follow BlueField BFB installation procedures

**References:**
- `/runs-lab-connect` skill for lab connectivity setup
- BlueField documentation in `infra/bluefield/docs/`
- BFB image setup in `infra/bluefield/deployment/`

## [URGENT] RUNS Lab Connectivity {#runs-lab-connectivity}
- turn connection to runs lab more seamless — streamline VPN setup, Proxmox access, SSM commands
- Improve lab onboarding documentation and automation

## [URGENT] ServerNIC Forwarding Stability {#servernic-forwarding-stability}
- identify stable forwarding paths for consistent packet forwarding across 3-subnet topology
- Validate end-to-end packet flow under various network conditions
- Ensure no packet loss in ServerNIC translation

## Architecture & Implementation

- Shift sequence number translation responsibility between sides
- BlueField-3 architecture: eSwitch for translation, DPA for connection setup and ISN generation, ARM core for DPDK setup
- RSS-based flow sharding
- Buffer ingress packets before handshake completes
- Explore using Corundum: https://github.com/corundum/corundum
- QUIC-style Connection ID for fast routing — widen the ISN-passing channel (T3 or T6 from `generated-isn-compression-options.md`; T8's 4 bytes are too narrow) to carry a structured CID `{version, backend_id, tenant_id, flow_nonce, auth_tag}` instead of just `V`. Enables: stateless ServerNIC routing by CID lookup, multi-backend fan-out via CID-encoded backend hint, connection survival across client NAT rebind.
  - Only worth implementing when fan-out > 1 (multiple ServerNICs or backend pools) or multi-tenant routing becomes a requirement. For the current single-ClientNIC / single-ServerNIC topology, plain `V` via T3 or T8 is sufficient.