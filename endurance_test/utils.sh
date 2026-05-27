#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

function power_on_board {
  local host="$1"
  local port=4902
  echo "Powering on board $host..."
  {
    sleep 1
    echo "target go"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
  if [ $? -eq 0 ]; then
    echo "Board $host powered on."
  else
    echo "Warning: Could not confirm power on for $host" >&2
  fi
}

function power_off_board {
  local host="$1"
  local port=4902
  echo "Powering off board $host..."
  {
    sleep 1
    echo "target halt"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
  if [ $? -eq 0 ]; then
    echo "Board $host halted."
  else
    echo "Warning: Could not confirm halted for $host" >&2
  fi
}

function reset_board {
  local host="$1"
  local port=4902
  echo "Resetting board $host..."
  {
    sleep 1
    echo "sys reset sys"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
}

function launch_reference_client {
  echo "Launching reference client (${REFERENCE_CLIENT})"

  # HACK: to re-launch the reference_client when it fails due to sigfault...
  exec 3> >(
  while true;
  do
    "${REFERENCE_CLIENT}" -g ${logs_dir}/reference_client.log -s ${ZipLanIp6} -p ${ZipPSK}
    sleep 1
  done
)
  sleep 1
}

function clean_exit {
  echo "Sutting down reference_client!"
  exec 3>&-
  wait

  mkdir -p "${logs_dir}"
  cp /var/log/zipgateway.log /var/log/ziprouter.serlog "${logs_dir}"
  echo "End Time: $(date)" >> "${logs_dir}/end_time"

  echo "Bye ..."

  kill 0
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
      if [ "${fields[0]}" != "slot" ]; then
        echo "bed_load: ${tsv}:${lineno}: first non-comment row must be the header (got '${fields[0]}')" >&2
        return 1
      fi
      header_seen=1
      continue
    fi

    local slot="${fields[0]}"
    if [ "${slot}" != "${BED_N}" ]; then
      echo "bed_load: ${tsv}:${lineno}: slot column '${slot}' does not match expected index ${BED_N}" >&2
      return 1
    fi

    local bootloader="${fields[5]}"
    [ "${bootloader}" = "-" ] && bootloader=""

    local firmware="${fields[6]}"
    if [ -n "${firmware}" ] && [ "${firmware}" != "-" ]; then
      case "${firmware}" in
        http://*|https://*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: firmware must be an http(s) URL (got '${firmware}')" >&2
          return 1
          ;;
      esac
    fi
    if [ -n "${bootloader}" ]; then
      case "${bootloader}" in
        http://*|https://*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: bootloader must be '-' or an http(s) URL (got '${bootloader}')" >&2
          return 1
          ;;
      esac
    fi

    local route="${fields[7]}"
    [ "${route}" = "-" ] && route=""

    local region="${fields[8]}"
    [ "${region}" = "-" ] && region=""
    if [ -n "${region}" ]; then
      case "${region}" in
        0x[0-9A-Fa-f]*) ;;
        *)
          echo "bed_load: ${tsv}:${lineno}: region must be hex 0x.. or '-' (got '${fields[8]}')" >&2
          return 1
          ;;
      esac
    fi

    BED_HOST+=( "${fields[1]}" )
    BED_BOARD+=( "${fields[2]}" )
    BED_DEVICE+=( "${fields[3]}" )
    BED_ROLE+=( "${fields[4]}" )
    BED_BOOTLOADER+=( "${bootloader}" )
    BED_FIRMWARE+=( "${fields[6]}" )
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

# Path under ${artifacts}/ mirroring Artifactory (everything after /artifactory/).
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

# Absolute local path for a downloaded artefact.
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
