#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

JLINK_TELNET_TIMEOUT_S="${JLINK_TELNET_TIMEOUT_S:-10}"
REFERENCE_CLIENT_RELAY_PID=""
CLEAN_EXIT_RUNNING=0

function power_on_board {
  local host="$1"
  local port=4902
  local rc
  echo "Powering on board $host..."
  if { sleep 1; echo "target go"; sleep 1; } \
       | timeout "${JLINK_TELNET_TIMEOUT_S}" telnet "$host" $port 2>/dev/null \
       | grep -q "OK"
  then
    rc=0
  else
    rc=${PIPESTATUS[2]}
  fi
  if [ "$rc" -eq 0 ]; then
    echo "Board $host powered on."
  else
    echo "Warning: Could not confirm power on for $host" >&2
  fi
}

function power_off_board {
  local host="$1"
  local port=4902
  local rc
  echo "Powering off board $host..."
  if { sleep 1; echo "target halt"; sleep 1; } \
       | timeout "${JLINK_TELNET_TIMEOUT_S}" telnet "$host" $port 2>/dev/null \
       | grep -q "OK"
  then
    rc=0
  else
    rc=${PIPESTATUS[2]}
  fi
  if [ "$rc" -eq 0 ]; then
    echo "Board $host halted."
  else
    echo "Warning: Could not confirm halted for $host" >&2
  fi
}

function reset_board {
  local host="$1"
  local port=4902
  local rc
  echo "Resetting board $host..."
  if { sleep 1; echo "sys reset sys"; sleep 1; } \
       | timeout "${JLINK_TELNET_TIMEOUT_S}" telnet "$host" $port 2>/dev/null \
       | grep -q "OK"
  then
    rc=0
  else
    rc=${PIPESTATUS[2]}
  fi
  return "$rc"
}

# Send a CLI command to a board's application UART (port 4901).
# Usage: board_cli <jlink_host> <command> [timeout_s]
function board_cli {
  local host="$1"
  local cmd="$2"
  local timeout_s="${3:-${JLINK_TELNET_TIMEOUT_S}}"
  local port=4901
  { sleep 1; echo "${cmd}"; sleep 1; } \
    | timeout "${timeout_s}" telnet "${host}" "${port}" 2>/dev/null
}

function launch_reference_client {
  echo "Launching reference client (${REFERENCE_CLIENT})"

  # HACK: to re-launch the reference_client when it fails due to sigfault...
  exec 3> >(
  set +e
  while true;
  do
    "${REFERENCE_CLIENT}" -g ${STEP_DIR}/reference_client.log -s ${ZipLanIp6} -p ${ZipPSK}
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      echo "Warning: reference_client exited with rc=${rc}; restarting in 1s" >&2
    fi
    sleep 1
  done
)
  REFERENCE_CLIENT_RELAY_PID=$!
  sleep 1
}

function clean_exit {
  if [ "${CLEAN_EXIT_RUNNING}" -eq 1 ]; then
    return 0
  fi
  CLEAN_EXIT_RUNNING=1
  trap - EXIT HUP INT TERM

  echo "Sutting down reference_client!"
  exec 3>&-
  wait_pid "${REFERENCE_CLIENT_RELAY_PID}" 5

  mkdir -p "${STEP_DIR}"
  if [[ -f "/var/log/zipgateway.log" ]]; then
    cp /var/log/zipgateway.log "${STEP_DIR}" || true
  else
    echo "/var/log/zipgateway.log not found"
  fi

  if [[ -f "/var/log/ziprouter.serlog" ]]; then
    cp /var/log/ziprouter.serlog "${STEP_DIR}" || true
  else
    echo "/var/log/ziprouter.serlog  not found"
  fi

  echo "End Time: $(date)" >> "${STEP_DIR}/end_time"

  echo "Bye ..."
  exit 0
}

function activate_radio_tone {
  echo "$(date): Activating radio tone"
  echo "setTxTone 1" > "${RAIL_TEST_908}"
  echo "setTxTone 1" > "${RAIL_TEST_916}"
}

function deactivate_radio_tone {
  echo "$(date): Deactivating radio tone"
  echo "setTxTone 0" > "${RAIL_TEST_908}"
  echo "setTxTone 0" > "${RAIL_TEST_916}"
}

function setup_rail_test {
  # To be sure, stop the tone
  echo "reset" > "${RAIL_TEST_908}"
  echo "reset" > "${RAIL_TEST_916}"
  sleep 1

  echo "setDebugMode 1" > "${RAIL_TEST_908}"
  echo "setDebugMode 1" > "${RAIL_TEST_916}"
  sleep 0.1

  echo "rx 0" > "${RAIL_TEST_908}"
  echo "rx 0" > "${RAIL_TEST_916}"
  sleep 0.1

  echo "freqOverride 908400000" > "${RAIL_TEST_908}"
  echo "freqOverride 916000000" > "${RAIL_TEST_916}"
  sleep 0.1
}

# Convert a compact duration ('72h', '30m', '45s', '3d') or a bare integer
# (seconds) to seconds on stdout. Returns non-zero on a bad expression so
# callers can validate and fail fast. Kept narrow on purpose: GNU date(1)
# does not accept '72h' style (only 'now + 72 hours'), and the conf format
# was documented as '72h, 30m', so this helper is the single place that
# bridges the gap.
duration_to_seconds() {
  local d="$1"
  case "$d" in
    ''|*[!0-9smhdSMHD]*) return 1 ;;
    *d|*D) echo $(( ${d%[dD]} * 86400 )) ;;
    *h|*H) echo $(( ${d%[hH]} * 3600 )) ;;
    *m|*M) echo $(( ${d%[mM]} * 60 )) ;;
    *s|*S) echo $(( ${d%[sS]} )) ;;
    *)     echo "${d}" ;;
  esac
}

# -- Bed description helpers ---------------------------------------------------
#
# Public surface after bed_load <tsv>:
#   BED_N                 number of slots
#   BED_HOST[i]           JLink-IP DNS name
#   BED_BOARD[i]          Commander --board family (e.g. brd4205b)
#   BED_DEVICE[i]         Commander --device token (e.g. ZGM230S)
#   BED_ROLE[i]           zniffer | controller | switch | door_lock | pir
#   BED_BOOTLOADER[i]     Artifactory URL ('' when '-')
#   BED_FIRMWARE[i]       Artifactory URL
#   BED_ROUTE[i]          PRIORITY_ROUTE_SET hex string ('' when '-')
#   BED_REGION[i]         MFG_ZWAVE_COUNTRY_FREQ hex ('' when '-')
#
# Iterators:
#   bed_iter_end_devices  prints slot indices whose role is not
#                         zniffer/controller, one per line.
#
# These helpers expect strict mode in the caller (set -euo pipefail).
# They do not set it here so sourcing utils.sh remains side-effect-free
# beyond function definitions.

bed_load() {
  local tsv="$1"
  if [ ! -f "${tsv}" ]; then
    echo "bed_load: TSV not found: ${tsv}" >&2
    return 1
  fi

  BED_N=0
  BED_HOST=()
  BED_BOARD=()
  BED_DEVICE=()
  BED_ROLE=()
  BED_BOOTLOADER=()
  BED_FIRMWARE=()
  BED_ROUTE=()
  BED_REGION=()

  local header_seen=0
  local lineno=0
  local raw
  while IFS= read -r raw || [ -n "${raw}" ]; do
    lineno=$((lineno + 1))
    # Strip CR (in case the file ever picks up CRLF).
    raw="${raw%$'\r'}"
    # Skip blank lines and comments.
    case "${raw}" in
      ''|\#*) continue ;;
    esac

    # Split on tabs.
    local IFS=$'\t'
    # shellcheck disable=SC2206 # intentional word-splitting on TAB
    local fields=( ${raw} )
    unset IFS

    if [ "${#fields[@]}" -ne 9 ]; then
      echo "bed_load: ${tsv}:${lineno}: expected 9 tab-separated fields, got ${#fields[@]}" >&2
      return 1
    fi

    if [ "${header_seen}" -eq 0 ]; then
      if [ "${fields[0]}" != "id" ]; then
        echo "bed_load: ${tsv}:${lineno}: first non-comment row must be the header (got '${fields[0]}')" >&2
        return 1
      fi
      header_seen=1
      continue
    fi

    local id="${fields[0]}"
    if [ "${id}" != "${BED_N}" ]; then
      echo "bed_load: ${tsv}:${lineno}: id column '${id}' does not match expected index ${BED_N}" >&2
      return 1
    fi

    local route="${fields[5]}"
    [ "${route}" = "-" ] && route=""

    local region="${fields[6]}"
    [ "${region}" = "-" ] && region=""
    if [ -n "${region}" ]; then
      case "${region}" in
        0x[0-9A-Fa-f]*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: region must be hex 0x.. or '-' (got '${fields[6]}')" >&2
          return 1
          ;;
      esac
    fi

    local firmware="${fields[7]}"
    if [ -n "${firmware}" ] && [ "${firmware}" != "-" ]; then
      case "${firmware}" in
        http://*|https://*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: firmware must be an http(s) URL (got '${firmware}')" >&2
          return 1
          ;;
      esac
    fi

    local bootloader="${fields[8]}"
    [ "${bootloader}" = "-" ] && bootloader=""
    if [ -n "${bootloader}" ]; then
      case "${bootloader}" in
        http://*|https://*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: bootloader must be '-' or an http(s) URL (got '${bootloader}')" >&2
          return 1
          ;;
      esac
    fi

    BED_HOST+=( "${fields[1]}" )
    BED_BOARD+=( "${fields[2]}" )
    BED_DEVICE+=( "${fields[3]}" )
    BED_ROLE+=( "${fields[4]}" )
    BED_BOOTLOADER+=( "${bootloader}" )
    BED_FIRMWARE+=( "${firmware}" )
    BED_ROUTE+=( "${route}" )
    BED_REGION+=( "${region}" )

    BED_N=$((BED_N + 1))
  done < "${tsv}"

  if [ "${header_seen}" -eq 0 ]; then
    echo "bed_load: ${tsv}: no header row found" >&2
    return 1
  fi
  if [ "${BED_N}" -eq 0 ]; then
    echo "bed_load: ${tsv}: no data rows" >&2
    return 1
  fi
}

bed_iter_end_devices() {
  local i
  for ((i = 0; i < BED_N; i++)); do
    case "${BED_ROLE[i]}" in
      zniffer|controller) ;;
      *) echo "${i}" ;;
    esac
  done
}

# Build the reference_client URI for one end-device slot.
#
# Format: 'dut-<slot>.<LOCATION> [<homeid>-<nodeid>-000]'
# NodeID = slot + 4 reflects the empirical ZGW SmartStart allocation
# on this bench: NodeID 1 = controller, 2..5 reserved by ZGW, end
# devices start at NodeID 6 = slot 2 + 4. If ZGW ever changes that
# allocation, this is the only place to update.
#
# Requires LOCATION (from conf) and the homeid passed by the caller.
bed_node_uri() {
  local slot="$1"
  local homeid="$2"
  printf 'dut-%s.%s [%s-%04d-000]' \
    "${slot}" "${LOCATION}" "${homeid}" "$((slot + 4))"
}

# Path under ${ARTIFACTS_DIR}/ mirroring Artifactory (everything after /artifactory/).
bed_artifact_relpath_from_url() {
  local url="$1"
  case "${url}" in
    */artifactory/*)
      echo "${url#*/artifactory/}"
      ;;
    *)
      echo "bed_artifact_relpath_from_url: not an Artifactory URL: ${url}" >&2
      return 1
      ;;
  esac
}

# Absolute local path for a downloaded artifact.
bed_artifact_local_path() {
  local artifacts_root="$1"
  local url="$2"
  local relpath
  relpath=$(bed_artifact_relpath_from_url "${url}")
  echo "${artifacts_root}/${relpath}"
}

# Unique http(s) URLs from bootloader and firmware columns.
bed_unique_artifact_urls() {
  local i
  for ((i = 0; i < BED_N; i++)); do
    [ -n "${BED_BOOTLOADER[i]}" ] && echo "${BED_BOOTLOADER[i]}"
    [ -n "${BED_FIRMWARE[i]}" ] && echo "${BED_FIRMWARE[i]}"
  done | sort -u
}

run_dir_attach() {
  local path="${1:-}"
  if [ -z "${path}" ]; then
    echo "run_dir_attach: <run_dir> required" >&2
    return 1
  fi
  if [ ! -d "${path}" ]; then
    echo "run_dir_attach: run dir not found: ${path}" >&2
    echo "                run ./00_init_test_run.sh first." >&2
    return 1
  fi
  RUN_DIR="$(cd "${path}" && pwd)"
  export RUN_DIR
  if [ -n "${ZGW_STAGE_DIR:-}" ]; then
    RUN_REMOTE_DIR="${ZGW_STAGE_DIR}/$(basename "${RUN_DIR}")"
    export RUN_REMOTE_DIR
  fi
}

wait_pid() {
  local pid="$1"
  local max_s="${2:-8}"
  local i=0
  while [ "${i}" -lt "${max_s}" ] && kill -0 "${pid}" 2>/dev/null; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
}
