#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-03 ZGW operational probe.
#
# Requirement
# -----------
# ST-03 asks for a periodic liveness probe against the ZGW resource
# directory while the load runs.
#
# Usage:
#   st03_zgw_probe.sh --out FILE --homeid HEX [options]
#
# Options:
#   --out FILE         CSV output path (required).
#   --homeid HEX       8 hex digits, no separators (required;
#                      e.g. C9136E8F).
#   --cadence-s SEC    seconds between samples (default 30).
#   --timeout-s SEC    per-sample resolve timeout in seconds (default 5;
#                      fractional allowed, e.g. 2.5).
#   --duration-s SEC   stop after this many seconds (default: run until
#                      SIGINT/SIGTERM).
#
# CSV columns: sample_iso,recv_iso,latency_s,hostname,address,status
#   status: ok | fail | timeout
#
# Stop with Ctrl+C; a final summary line is printed to stderr.

set -uo pipefail

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

OUT=""
HOMEID=""
CADENCE_S=30
TIMEOUT_S=5
DURATION_S=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)        OUT="${2:-}"; shift 2 ;;
    --homeid)     HOMEID="${2:-}"; shift 2 ;;
    --cadence-s)  CADENCE_S="${2:-}"; shift 2 ;;
    --timeout-s)  TIMEOUT_S="${2:-}"; shift 2 ;;
    --duration-s) DURATION_S="${2:-}"; shift 2 ;;
    -h|--help)    usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [ -z "${OUT}" ]; then
  echo "Error: --out is required." >&2
  usage 2
fi

if [ -z "${HOMEID}" ]; then
  echo "Error: --homeid is required." >&2
  usage 2
fi

if ! command -v avahi-resolve >/dev/null 2>&1; then
  echo "Error: avahi-resolve not found (install avahi-utils)." >&2
  exit 3
fi

HOMEID_UC=$(echo "${HOMEID}" | tr '[:lower:]' '[:upper:]')
if [[ ! "${HOMEID_UC}" =~ ^[0-9A-F]{8}$ ]]; then
  echo "Error: --homeid must be exactly 8 hex digits (got '${HOMEID}')." >&2
  exit 2
fi
# ZGW advertises its controller resource as zw<HomeID>0001.local.
# Assumes that the controller's node ID is 1.
HOSTNAME_MDNS="zw${HOMEID_UC}0001.local"

mkdir -p "$(dirname "${OUT}")"
echo "sample_iso,recv_iso,latency_s,hostname,address,status" > "${OUT}"
echo "ST-03 ZGW probe -> ${OUT}" >&2
duration_disp="until-signal"
[ -n "${DURATION_S}" ] && duration_disp="${DURATION_S}s"
echo "  target=${HOSTNAME_MDNS} cadence=${CADENCE_S}s timeout=${TIMEOUT_S}s duration=${duration_disp}" >&2

samples=0
oks=0
fails=0
timeouts=0
start_s=$(date +%s)

summary() {
  echo "ST-03 ZGW probe stopped: samples=${samples} ok=${oks} fail=${fails} timeout=${timeouts}" >&2
  echo "  CSV: ${OUT}" >&2
}
trap 'summary; exit 0' INT TERM

while true; do
  if [ -n "${DURATION_S}" ] && [ "$(( $(date +%s) - start_s ))" -ge "${DURATION_S}" ]; then
    break
  fi

  send_ns=$(date +%s%N)
  sample_iso=$(date -u -d "@$((send_ns/1000000000))" +%FT%T.%3NZ)
  if reply=$(timeout "${TIMEOUT_S}" avahi-resolve -n "${HOSTNAME_MDNS}" 2>/dev/null); then
    address=$(echo "${reply}" | awk '{print $2}')
    if [ -n "${address}" ]; then status="ok"; oks=$((oks+1)); else status="fail"; fails=$((fails+1)); fi
  else
    address=""
    status="timeout"; timeouts=$((timeouts+1))
  fi
  recv_ns=$(date +%s%N)
  recv_iso=$(date -u -d "@$((recv_ns/1000000000))" +%FT%T.%3NZ)
  latency_s=$(awk -v a="${send_ns}" -v b="${recv_ns}" 'BEGIN{printf "%.3f", (b-a)/1e9}')
  [ "${status}" = "timeout" ] && latency_s="${TIMEOUT_S}"
  echo "${sample_iso},${recv_iso},${latency_s},${HOSTNAME_MDNS},${address},${status}" >> "${OUT}"
  samples=$((samples+1))

  sleep "${CADENCE_S}"
done

summary
