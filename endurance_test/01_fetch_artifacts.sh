#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

script_folder=$(dirname "$0")

if [ ! -f "${script_folder}/conf" ]; then
  echo "Error: conf file not found in ${script_folder}" >&2
  exit 1
fi
if [ ! -f "${script_folder}/utils.sh" ]; then
  echo "Error: utils.sh not found in ${script_folder}" >&2
  exit 1
fi

source "${script_folder}/conf"
source "${script_folder}/utils.sh"

if [ -z "${artifacts:-}" ]; then
  echo "Error: artifacts variable is not set in conf." >&2
  exit 1
fi
if [ -z "${BED_TSV:-}" ]; then
  echo "Error: BED_TSV variable is not set in conf." >&2
  exit 1
fi

target_dir="${script_folder}/${artifacts}"
mkdir -p "${target_dir}"

if [ -z "${artifacts_url:-}" ] || [ "${artifacts_url}" = "not used in this test" ]; then
  cat <<EOF
Artifacts download is disabled for this test bed configuration.
Place the required firmware files manually under:
  ${target_dir}
EOF
  echo "Reminder: place zipgateway-7.18.03-Linux-armhf.deb under ./artifacts/."
  exit 0
fi

if ! command -v wget >/dev/null 2>&1; then
  echo "Error: wget is not installed." >&2
  exit 1
fi

# Layout selector: "col" (gsdk-generic-development / Circle of Life
# pipeline) or "z-wave" (zwave-conan-dev / Z-Wave pipeline)
layout="${artifacts_layout:-col}"

bed_load "${BED_TSV}"

# Distinct board families across the bed (one fetch loop per board).
bed_boards() {
  local i
  for ((i = 0; i < BED_N; i++)); do
    echo "${BED_BOARD[i]}"
  done | sort -u
}

# Firmware basenames belonging to a given board.
bed_firmware_for_board() {
  local want="$1"
  local i
  for ((i = 0; i < BED_N; i++)); do
    if [ "${BED_BOARD[i]}" = "${want}" ]; then
      echo "${BED_BOOTLOADER[i]}"
      echo "${BED_FIRMWARE[i]}"
    fi
  done | sort -u
}

# Application firmware basenames (excluding bootloaders) belonging to a
# given board. Used for the symbol-bundle fetch in the z-wave layout.
bed_app_firmware_for_board() {
  local want="$1"
  local i
  for ((i = 0; i < BED_N; i++)); do
    if [ "${BED_BOARD[i]}" = "${want}" ]; then
      echo "${BED_FIRMWARE[i]}"
    fi
  done | sort -u
}

fetch_col() {
  wget -nc -P "${target_dir}" "${artifacts_url}/build.xml"
  wget -nc -P "${target_dir}" "${artifacts_url}/conan.lock"

  local board name
  while IFS= read -r board; do
    while IFS= read -r name; do
      wget -nc -P "${target_dir}" \
        "${artifacts_url}/demo-applications.zip!/zwave_sample_app/${board}/${name}"
    done < <(bed_firmware_for_board "${board}")
  done < <(bed_boards)
}

fetch_z_wave() {
  local debug_dir="${target_dir}/debug"
  mkdir -p "${debug_dir}"

  local meta
  for meta in package-info.json zwave_complete_lockfile.lock; do
    wget -nc -P "${target_dir}" "${artifacts_url}/${meta}" \
      || echo "Note: could not fetch ${meta}; skipping." >&2
  done

  local board name app_name
  while IFS= read -r board; do
    while IFS= read -r name; do
      wget -nc -P "${target_dir}" "${artifacts_url}/demos/${board}/${name}"
    done < <(bed_firmware_for_board "${board}")

    # Symbol bundles live only under debug/<board>/<app>.zip
    while IFS= read -r app_name; do
      wget -nc -P "${debug_dir}" \
        "${artifacts_url}/debug/${board}/${app_name%.hex}.zip" \
        || echo "Note: could not fetch ${app_name%.hex}.zip; skipping." >&2
    done < <(bed_app_firmware_for_board "${board}")
  done < <(bed_boards)
}

case "${layout}" in
  col)
    fetch_col
    ;;
  z-wave)
    fetch_z_wave
    ;;
  *)
    echo "Error: unknown artifacts_layout='${layout}' (expected 'col' or 'z-wave')." >&2
    exit 1
    ;;
esac

echo "Artifacts ready in ${target_dir} (layout=${layout})."
echo "Reminder: place zipgateway-7.18.03-Linux-armhf.deb under ./artifacts/."
