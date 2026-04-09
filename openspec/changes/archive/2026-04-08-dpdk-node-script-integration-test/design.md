## Context

`experiments/zero-rtt-dpdk/run_experiment.sh` is a monolithic 440-line orchestrator that handles discovery, build, startup, testing, log collection, and validation in one script. Node scripts under `experiments/zero-rtt-dpdk/nodes/` (server.sh, servernic.sh, clientnic.sh, client.sh) already implement per-VM logic and are used interactively, but automation uses only `run_experiment.sh`.

The goal is to make `run_experiment.sh` delegate per-VM startup to the node scripts via SSM, rather than inlining the same logic inline.

Known edge cases (from issue #11):
- `clientnic.sh` uses `exec` (foreground) and a `cleanup` trap — unsuitable for SSM background mode as-is; requires wrapping in `setsid ... &`
- `client.sh` has an interactive `while IFS= read -r _input` loop — must be bypassed by calling `client.py` directly
- GW MAC discovery in `clientnic.sh` uses the EC2 API (IAM may block this from VM); fall back to reading `ServerNIC:/sys/class/net/eth0/address` from the orchestrator (already done in current `run_experiment.sh`)
- Git safe.directory error occurs when root runs `git pull` on a repo owned by `ec2-user`; add `git config --global --add safe.directory` before pulls

## Goals / Non-Goals

**Goals:**
- `run_experiment.sh` starts each VM using its node script via SSM `send-command`
- Per-VM logs are captured to `/tmp/<vm>.log` on each VM and fetched for display
- GW MAC is discovered by the orchestrator (via SSM `cat /sys/class/net/eth0/address` on ServerNIC) and passed as an argument to `clientnic.sh`
- Client runs non-interactively by calling `client.py` directly (bypassing `client.sh`'s read loop)
- Git safe.directory is configured before git pull on each VM
- Report saved to `experiments/zero-rtt-dpdk/reports/`
- zero-rtt-integration-tester skill updated to document the node-script flow

**Non-Goals:**
- Modifying node scripts to make them automation-aware (they stay interactive-friendly)
- Changing `clientnic/dpdk/` build system or source
- Parallelising VM startup (sequential order is required: Server → ServerNIC → ClientNIC → Client)

## Decisions

**Decision: Orchestrator wraps node scripts in `setsid ... &` rather than modifying them**
- Node scripts use `exec` (clientnic.sh) and interactive loops (client.sh) — changing them would break interactive use
- Wrapping in `setsid bash nodes/X.sh ... < /dev/null >> /tmp/X.log 2>&1 &` keeps them unchanged
- Alternative (add `--non-interactive` flag to each script) rejected: more invasive, no benefit

**Decision: Client is run via `client.py` directly, not `client.sh`**
- `client.sh`'s interactive `read` loop cannot be piped non-interactively in SSM without `expect` or a co-process
- `client.py` accepts `--mode repeated --count 1` which gives exactly one connection and exits — already supported
- Alternative (pipe `\n` into client.sh): fragile, timing-dependent

**Decision: GW MAC discovered by orchestrator, passed as argument to `clientnic.sh`**
- `clientnic.sh` already accepts `[gw-mac]` as `$1`; EC2 API calls from VMs may fail due to IAM
- Orchestrator has full AWS credentials; reading ServerNIC's `/sys/class/net/eth0/address` via SSM is reliable
- This is already the pattern used in the current `run_experiment.sh`

**Decision: Git safe.directory added before each `git pull` on VMs**
- Scripts run as root via SSM; repo is owned by `ec2-user` → git ownership error
- `git config --global --add safe.directory /home/ec2-user/zero-rtt-demo` before pull resolves this
- Already called out in issue #11

## Risks / Trade-offs

- `clientnic.sh` `cleanup` trap fires on EXIT and prints validator instructions — harmless in SSM but produces extra log noise → **Mitigation**: orchestrator ignores trailing log lines after the binary is killed
- SSM `send-command` with a background process returns before the process is ready; existing `sleep` delays between steps handle this → **Mitigation**: keep existing sleep cadence (3s after Server, 2s after ServerNIC, 4s after ClientNIC)
- Node scripts include `git pull` — if the repo has local changes on a VM the pull may fail → **Mitigation**: pull uses `|| true` (already in node scripts); orchestrator also does a pre-pull pass

## Open Questions

- Should the build step (`SKIP_BUILD=0` path in `clientnic.sh`) be triggered via the node script, or kept inline in the orchestrator for clearer control? Currently leaning toward keeping `SKIP_BUILD=1` in automation (build already happened at provision time or in a prior run) and having the orchestrator do a rebuild only if needed.
