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
# Usage: ./flow_rule.sh --src-ip <ip> --dst-ip <ip> --src-port <port> \
#          --dst-port <port> --delta <int32> [--direction sub|add] \
#          [--port-id <id>] [--image-tag <tag>] [--baseline-file <path>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hosts.sh
source "${SCRIPT_DIR}/lib/hosts.sh"

IMAGE_TAG="eswitch-probe:latest"
BASELINE_FILE="${SCRIPT_DIR}/../reports/baseline.txt"
PROBE_ARGS=()

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

# EAL args precede the "--" separator; the probe's own rule-parameter
# args follow it (probe.c calls rte_eal_init first). device_arg, when
# non-empty, is appended to the mlx5 auxiliary device argument.
run_probe() {
    local device_arg="$1"
    local dev_spec="auxiliary:mlx5_core.sf.2"
    [[ -n "${device_arg}" ]] && dev_spec="${dev_spec},${device_arg}"
    dpu_run "docker run --rm --privileged --network host ${IMAGE_TAG} -l 0-1 -n 4 -a ${dev_spec} -- ${PROBE_ARGS[*]}"
}

echo "Attempting rule install (delta=${PROBE_ARGS[*]})..."
if OUTPUT="$(run_probe "" 2>&1)"; then
    echo "${OUTPUT}"
    echo "RESULT: rule accepted"
    exit 0
fi

echo "First attempt failed; retrying with dv_flow_en=2 before recording a negative result..." >&2
echo "${OUTPUT}" >&2
if OUTPUT="$(run_probe "dv_flow_en=2" 2>&1)"; then
    echo "${OUTPUT}"
    echo "RESULT: rule accepted (required dv_flow_en=2)"
    exit 0
fi

echo "${OUTPUT}"
echo "RESULT: rule rejected (verbatim error above)"
exit 1
