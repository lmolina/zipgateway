#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# ST-02 false-dead tailer (node false-dead events).
#
# Usage:
#   st02_tailer.sh --out FILE --homeid HEX --ssh-target USER@HOST [options]

set -uo pipefail

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
  echo "  --out FILE --homeid HEX --ssh-target USER@HOST"
  echo "  [--log PATH] [--event-re RE] [--nodeid-re RE]"
  echo "  [--resolve-timeout-s S] [--probe-timeout-s S] [--settle-s S]"
  exit "${1:-2}"
}

OUT=""
HOMEID=""
SSH_TARGET=""
LOG_PATH="/var/log/zipgateway.log"
EVENT_RE="Node [0-9]+ is now failing"
NODEID_RE="Node [0-9]+"
RESOLVE_TIMEOUT_S=5
PROBE_TIMEOUT_S=30
SETTLE_S=1

while [ $# -gt 0 ]; do
  case "$1" in
    --out)               OUT="${2:-}"; shift 2 ;;
    --homeid)            HOMEID="${2:-}"; shift 2 ;;
    --ssh-target)        SSH_TARGET="${2:-}"; shift 2 ;;
    --log)               LOG_PATH="${2:-}"; shift 2 ;;
    --event-re)          EVENT_RE="${2:-}"; shift 2 ;;
    --nodeid-re)         NODEID_RE="${2:-}"; shift 2 ;;
    --resolve-timeout-s) RESOLVE_TIMEOUT_S="${2:-}"; shift 2 ;;
    --probe-timeout-s)   PROBE_TIMEOUT_S="${2:-}"; shift 2 ;;
    --settle-s)          SETTLE_S="${2:-}"; shift 2 ;;
    -h|--help)           usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [ -z "${OUT}" ] || [ -z "${HOMEID}" ] || [ -z "${SSH_TARGET}" ]; then
  echo "Error: --out, --homeid, and --ssh-target are required." >&2
  usage 2
fi

if ! command -v avahi-resolve >/dev/null 2>&1; then
  echo "Error: avahi-resolve not found (install avahi-utils)." >&2
  exit 3
fi

if ! command -v ping >/dev/null 2>&1; then
  echo "Error: ping not found." >&2
  exit 3
fi

HOMEID_LC=$(echo "${HOMEID}" | tr '[:upper:]' '[:lower:]')
if [[ ! "${HOMEID_LC}" =~ ^[0-9a-f]{8}$ ]]; then
  echo "Error: --homeid must be exactly 8 hex digits (got '${HOMEID}')." >&2
  exit 2
fi

mkdir -p "$(dirname "${OUT}")"
echo "event_iso,probe_iso,nodeid,mdns,target,status,raw_event" > "${OUT}"
echo "ST-02 false-dead tailer -> ${OUT}" >&2
echo "  ssh=${SSH_TARGET} homeid=${HOMEID_LC} resolve_timeout=${RESOLVE_TIMEOUT_S}s probe_timeout=${PROBE_TIMEOUT_S}s" >&2

events=0
false_dead=0
true_dead=0
noparse=0
noresolve=0

summary() {
  echo "ST-02 tailer stopped: events=${events} false_dead=${false_dead} true_dead=${true_dead} noresolve=${noresolve} noparse=${noparse}" >&2
  echo "  CSV: ${OUT}" >&2
}
trap 'summary; exit 0' INT TERM

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15)

csv_quote() {
  local s="$1"
  s="${s//\"/\"\"}"
  printf '"%s"' "${s}"
}

strip_ansi() {
  printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'
}

# zw<homeid><node4hex>.local (e.g. zwf7c7353d0006.local)
node_mdns() {
  local nodeid="$1"
  printf 'zw%s%04x.local' "${HOMEID_LC}" "${nodeid}"
}

resolve_node() {
  local mdns="$1"
  local reply address
  if reply=$(timeout "${RESOLVE_TIMEOUT_S}" avahi-resolve -n "${mdns}" 2>/dev/null); then
    address=$(printf '%s\n' "${reply}" | awk '{print $2}')
    if [ -n "${address}" ]; then
      printf '%s' "${address}"
      return 0
    fi
  fi
  return 1
}

probe_ip() {
  local target="$1"
  timeout "${PROBE_TIMEOUT_S}" ping -c1 -W"${PROBE_TIMEOUT_S}" "${target}" >/dev/null 2>&1
}

ssh "${ssh_opts[@]}" "${SSH_TARGET}" "tail -n0 -F '${LOG_PATH}'" 2>/dev/null \
  | grep --line-buffered -E "${EVENT_RE}" \
  | while IFS= read -r raw_line; do
      line=$(strip_ansi "${raw_line}")
      event_iso=$(date -u +%FT%T.%3NZ)
      events=$((events+1))

      match=$(printf '%s\n' "${line}" | grep -oE "${NODEID_RE}" | head -n1 || true)
      nodeid=$(printf '%s\n' "${match}" | grep -oE '[0-9]+' | head -n1 || true)

      if [ -z "${nodeid}" ]; then
        noparse=$((noparse+1))
        probe_iso=$(date -u +%FT%T.%3NZ)
        printf '%s,%s,,,%s,%s\n' \
          "${event_iso}" "${probe_iso}" "noparse" "$(csv_quote "${line}")" >> "${OUT}"
        continue
      fi

      [ -n "${SETTLE_S}" ] && [ "${SETTLE_S}" != "0" ] && sleep "${SETTLE_S}"

      mdns=$(node_mdns "${nodeid}")
      target=""
      if target=$(resolve_node "${mdns}"); then
        if probe_ip "${target}"; then
          status="false_dead"; false_dead=$((false_dead+1))
        else
          status="true_dead"; true_dead=$((true_dead+1))
        fi
      else
        status="noresolve"; noresolve=$((noresolve+1))
      fi

      probe_iso=$(date -u +%FT%T.%3NZ)
      printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "${event_iso}" "${probe_iso}" "${nodeid}" "${mdns}" "${target}" "${status}" \
        "$(csv_quote "${line}")" >> "${OUT}"
    done

summary
