#!/usr/bin/env bash
# Installs the composed e-switch rule (5-tuple match, TCP seq/ack modify,
# egress toward the host port) by invoking the probe container with the
# rule parameters as CLI arguments, and captures the returned handle or
# the verbatim error text.
#
# Reads the DOCA/DPDK versions recorded by baseline.sh first, so a build
# that predates TCP seq/ack modify support is reported as a tooling
# limitation rather than misreported as a hardware NO (design.md Risks).
# Retries with dv_flow_en=2 on the device argument before recording any
# negative result, since infra/bluefield/deployment/Dockerfile uses that
# flag on this hardware and omitting it could produce a false NO
# (design.md Open Questions).
#
# The probe is started DETACHED and left running. It keeps the rule
# installed for --hold-secs, so traffic.sh's packets arrive while the entry
# is live; run_probe.sh collects the container's counters afterwards. A
# synchronous run would install and tear down the rule before any traffic
# existed, and the hardware counter would always read zero.
#
# Usage: ./flow_rule.sh --src-ip <ip> --dst-ip <ip> --src-port <port> \
#          --dst-port <port> --delta <int32> [--direction sub|add] \
#          [--port-id <id>] [--image-tag <tag>] [--baseline-file <path>] \
#          [--hold-secs <n>] [--container-name <name>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

IMAGE_TAG="eswitch-probe:latest"
BASELINE_FILE="${SCRIPT_DIR}/../reports/baseline.txt"
PROBE_ARGS=()

# How long the probe keeps the rule installed. Must comfortably exceed
# traffic.sh's capture window (default 5s) plus SSH round-trip latency.
HOLD_SECS="${PROBE_HOLD_SECS:-30}"
CONTAINER_NAME="${PROBE_CONTAINER_NAME:-eswitch-probe}"
# Seconds to wait for the probe to report its rule live before concluding
# the install failed.
MARKER_TIMEOUT="${PROBE_MARKER_TIMEOUT:-45}"
RULE_INSTALLED_MARKER="RULE INSTALLED"

# design.md's Context confirms DOCA 3.0.0058 with libdoca_flow is the
# installed, working toolchain on bluefield-runs3-dpu; gotchas.md warns
# that older DOCA/rte_flow builds may lack raw TCP seq/ack modify
# entirely. A recorded major version below this is reported as a tooling
# limitation rather than run through the probe and misread as a hardware
# NO (design.md Risks).
MIN_DOCA_MAJOR="${MIN_DOCA_MAJOR:-3}"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# Returns 1 (unsupported) when the recorded DOCA version's major number is
# below MIN_DOCA_MAJOR; returns 0 (proceed) when it parses as supported or
# when it cannot be parsed at all (an unparseable version is not evidence
# of a tooling limitation, so the probe still runs).
check_doca_version_supported() {
    local doca_ver="$1" major
    major="$(echo "${doca_ver}" | grep -oE '^[0-9]+' || true)"
    if [[ -z "${major}" ]]; then
        echo "WARNING: could not parse DOCA version '${doca_ver}'; proceeding without a tooling-limitation pre-check" >&2
        return 0
    fi
    [[ "${major}" -ge "${MIN_DOCA_MAJOR}" ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image-tag) IMAGE_TAG="$2"; shift 2 ;;
        --baseline-file) BASELINE_FILE="$2"; shift 2 ;;
        --hold-secs) HOLD_SECS="$2"; shift 2 ;;
        --container-name) CONTAINER_NAME="$2"; shift 2 ;;
        --src-ip|--dst-ip|--src-port|--dst-port|--delta|--direction|--port-id)
            PROBE_ARGS+=("$1" "$2"); shift 2 ;;
        *) fail "unrecognised argument: $1" ;;
    esac
done

if [[ ${#PROBE_ARGS[@]} -eq 0 ]]; then
    fail "no rule parameters given (need at least --src-ip/--dst-ip/--src-port/--dst-port/--delta)"
fi

if [[ -f "${BASELINE_FILE}" ]]; then
    DOCA_VERSION_STR="$(grep -A1 '## DOCA version' "${BASELINE_FILE}" | tail -n1)"
    DPDK_VERSION_STR="$(grep -A1 '## DPDK version' "${BASELINE_FILE}" | tail -n1)"
    echo "Recorded DOCA version: ${DOCA_VERSION_STR}"
    echo "Recorded DPDK version: ${DPDK_VERSION_STR}"

    if ! check_doca_version_supported "${DOCA_VERSION_STR}"; then
        echo "RESULT: tooling limitation (DOCA ${DOCA_VERSION_STR} predates DOCA ${MIN_DOCA_MAJOR}.x; TCP seq/ack modify support is not confirmed on this build)"
        exit 3
    fi
else
    echo "WARNING: no baseline file at ${BASELINE_FILE}; cannot pre-check DOCA/DPDK versions" >&2
fi

# Removes any container left behind by an earlier run or a failed attempt,
# so --name is always free and stale logs are never mistaken for this run's.
clear_container() {
    dpu_run "docker rm -f ${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

# EAL args precede the "--" separator; the probe's own rule-parameter args
# follow it (probe.c calls rte_eal_init first). device_arg, when non-empty,
# is appended to the mlx5 device argument. Started detached: the container
# outlives this script so the rule is still installed when traffic.sh runs.
start_probe() {
    local device_arg="$1"
    local dev_spec="${PROBE_EAL_DEV}"
    [[ -n "${device_arg}" ]] && dev_spec="${dev_spec},${device_arg}"
    # No --rm: the container must survive exit so run_probe.sh can read its
    # counters out of `docker logs` after the hold window closes.
    dpu_run "docker run -d --name ${CONTAINER_NAME} --privileged --network host ${IMAGE_TAG} \
             -l 0-1 -n 4 -a ${dev_spec} -- ${PROBE_ARGS[*]} --hold-secs ${HOLD_SECS}"
}

# Blocks until the probe reports its rule live, the container exits without
# ever reporting it, or MARKER_TIMEOUT elapses. Returns 0 only on the marker.
await_rule_installed() {
    local waited=0
    while [[ "${waited}" -lt "${MARKER_TIMEOUT}" ]]; do
        if dpu_run "docker logs ${CONTAINER_NAME} 2>&1 | grep -q '${RULE_INSTALLED_MARKER}'"; then
            return 0
        fi
        if ! dpu_run "docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} 2>/dev/null | grep -q true"; then
            return 1  # exited without installing the rule
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# Tries one device argument. On success leaves the container running and
# prints its logs so far; on failure prints them and clears the container.
attempt_install() {
    local device_arg="$1"
    clear_container
    if ! start_probe "${device_arg}" >/dev/null 2>&1; then
        echo "docker run failed to start the probe container" >&2
        return 1
    fi
    if await_rule_installed; then
        dpu_run "docker logs ${CONTAINER_NAME} 2>&1" || true
        return 0
    fi
    dpu_run "docker logs ${CONTAINER_NAME} 2>&1" >&2 || true
    clear_container
    return 1
}

echo "Attempting rule install (args=${PROBE_ARGS[*]}, hold=${HOLD_SECS}s)..."
if attempt_install ""; then
    echo "RESULT: rule accepted"
    echo "CONTAINER: ${CONTAINER_NAME}"
    exit 0
fi

echo "First attempt failed; retrying with dv_flow_en=2 before recording a negative result..." >&2
if attempt_install "dv_flow_en=2"; then
    echo "RESULT: rule accepted (required dv_flow_en=2)"
    echo "CONTAINER: ${CONTAINER_NAME}"
    exit 0
fi

echo "RESULT: rule rejected (verbatim error above)"
exit 1
