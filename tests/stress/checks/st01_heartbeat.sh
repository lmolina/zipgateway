#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-01 heartbeat probe (NCP tx-queue lockup).
#
# Requirement
# -----------
# ST-01 is an NCP tx-queue lockup: under sustained load the radio stops
# completing transmissions even though nothing crashed.
#
# Usage:
#   st01_heartbeat.sh --out FILE [options]
#
# Options:
#   --out FILE         CSV output path (required).
#   --homeid HEX       8 hex digits, no separators (e.g. C9136E8F). If
#                      omitted, auto-detected over SSH from the ZGW log.
#   --cadence-s SEC    seconds between samples (default 10).
#   --timeout-s SEC    per-sample resolve timeout in seconds (default 5;
#                      fractional allowed, e.g. 2.5).
#   --duration-s SEC   stop after this many seconds (default: run until
#                      SIGINT/SIGTERM).
#   --conf FILE        conf to source for ZGW_HOST/ZGW_USER (used only for
#                      HomeID auto-detect). Default: ../conf next to this
#                      script's test dir.
#
# CSV columns: sample_iso,recv_iso,latency_s,hostname,address,status
#   status: ok | fail | timeout
#
# Stop with Ctrl+C; a final summary line is printed to stderr.

set -uo pipefail

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-2}"
}

OUT=""
HOMEID=""
CADENCE_S=10
TIMEOUT_S=5
DURATION_S=""
CONF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --out)        OUT="${2:-}"; shift 2 ;;
    --homeid)     HOMEID="${2:-}"; shift 2 ;;
    --cadence-s)  CADENCE_S="${2:-}"; shift 2 ;;
    --timeout-s)  TIMEOUT_S="${2:-}"; shift 2 ;;
    --duration-s) DURATION_S="${2:-}"; shift 2 ;;
    --conf)       CONF="${2:-}"; shift 2 ;;
    -h|--help)    usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [ -z "${OUT}" ]; then
  echo "Error: --out is required." >&2
  usage 2
fi

if ! command -v avahi-resolve >/dev/null 2>&1; then
  echo "Error: avahi-resolve not found (install avahi-utils)." >&2
  exit 3
fi

# Resolve conf path for HomeID auto-detect (default: the test dir that
# owns checks/, i.e. ../conf relative to this script).
script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ -z "${CONF}" ]; then
  CONF="$(cd "${script_dir}/.." && pwd)/conf"
fi

if [ -z "${HOMEID}" ]; then
  if [ ! -f "${CONF}" ]; then
    echo "Error: no --homeid and conf not found at ${CONF} for auto-detect." >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  source "${CONF}"
  if [ -z "${ZGW_HOST:-}" ] || [ -z "${ZGW_USER:-}" ]; then
    echo "Error: ZGW_HOST/ZGW_USER not set in ${CONF}; cannot auto-detect HomeID." >&2
    exit 2
  fi
  echo "Auto-detecting HomeID from ${ZGW_USER}@${ZGW_HOST} ..." >&2
  HOMEID=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "${ZGW_USER}@${ZGW_HOST}" \
    "grep -m1 HomeID /var/log/zipgateway.log 2>/dev/null | cut -f4 -d' '" || true)
  HOMEID="${HOMEID//[![:alnum:]]/}"
  if [ -z "${HOMEID}" ]; then
    echo "Error: could not auto-detect HomeID from the ZGW log." >&2
    echo "       pass --homeid HEX explicitly." >&2
    exit 2
  fi
fi

HOMEID_UC=$(echo "${HOMEID}" | tr '[:lower:]' '[:upper:]')
# ZGW advertises its controller resource as zw<HomeID>0001.local.
HOSTNAME_MDNS="zw${HOMEID_UC}0001.local"

mkdir -p "$(dirname "${OUT}")"
echo "sample_iso,recv_iso,latency_s,hostname,address,status" > "${OUT}"
echo "ST-01 heartbeat -> ${OUT}" >&2
echo "  target=${HOSTNAME_MDNS} cadence=${CADENCE_S}s timeout=${TIMEOUT_S}s duration=${DURATION_S:-until-signal}s" >&2

samples=0
oks=0
fails=0
timeouts=0
start_s=$(date +%s)

summary() {
  echo "ST-01 heartbeat stopped: samples=${samples} ok=${oks} fail=${fails} timeout=${timeouts}" >&2
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
  # Fractional seconds, 3 decimals (ms resolution kept, seconds as the unit).
  latency_s=$(awk -v a="${send_ns}" -v b="${recv_ns}" 'BEGIN{printf "%.3f", (b-a)/1e9}')
  [ "${status}" = "timeout" ] && latency_s="${TIMEOUT_S}"
  echo "${sample_iso},${recv_iso},${latency_s},${HOSTNAME_MDNS},${address},${status}" >> "${OUT}"
  samples=$((samples+1))

  sleep "${CADENCE_S}"
done

summary
