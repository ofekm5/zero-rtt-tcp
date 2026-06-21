# Sprint 4: Shared runner core and Proxmox SSH-gateway transport

## Tasks
- 4.1 Factor the shared runner core into `experiments/utils/run_core.sh`
- 4.2 Add the Proxmox SSH-gateway transport in `experiments/utils/ssh_lab.sh`
- 4.3 Add the Proxmox runner `experiments/proxmox/run_experiment.sh` using core + ssh_lab

## Acceptance criteria
- C1: `run_core.sh` has valid bash syntax — verify: `bash -n experiments/utils/run_core.sh`
- C2: `ssh_lab.sh` has valid bash syntax — verify: `bash -n experiments/utils/ssh_lab.sh`
- C3: Proxmox runner has valid bash syntax — verify: `bash -n experiments/proxmox/run_experiment.sh`
- C4: both runners source the shared core (R1 — same mechanism) — verify: `grep -q 'run_core.sh' experiments/dpdk/run_experiment.sh && grep -q 'run_core.sh' experiments/proxmox/run_experiment.sh`
- C5: Proxmox runner sources the SSH-gateway transport — verify: `grep -q 'ssh_lab.sh' experiments/proxmox/run_experiment.sh`
- C6: AWS runner has been refactored to source `run_core.sh` (no duplication of the core flow) — verify: `grep -q 'run_core.sh' experiments/dpdk/run_experiment.sh`

## Out of scope
- Live Proxmox execution (requires gateway lab access) — task 4.4 is a manual review step excluded from this sprint
- Live AWS execution — task 3.4 is a manual review step excluded from all code-only sprints
- Changes to the analyzer or `measure.sh`
