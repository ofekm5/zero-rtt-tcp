# RUNS3 BlueField BFB Reinstall

## Problem
BlueField DPU is offline for unknown reason. Need to reinstall its BFB (BlueField firmware image).

## Solution
1. Use `/runs-lab-connect` to connect to the gateway
2. From gateway, connect to BF BMC at 10.13.36.233
3. Maintain persistent connection to gateway for multi-terminal access during reinstall process
4. Follow BlueField BFB installation procedures

## References
- `/runs-lab-connect` skill for lab connectivity setup
- BlueField documentation in `infra/bluefield/docs/`
- BFB image setup in `infra/bluefield/deployment/`
