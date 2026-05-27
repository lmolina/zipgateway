#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -e
set -x
set -u
set -o pipefail

script_folder=$(dirname "$0")

function cleanup_boards {
  local i
  for ((i = 0; i < BED_N; i++)); do
    echo
    echo "=========================================="
    echo "dut_$i: ${BED_HOST[i]}"

    # Some firmware version may break the radio board, thus the need for a
    # recover.
    commander device recover --ip "${BED_HOST[i]}"

    commander device masserase --ip "${BED_HOST[i]}"
    commander device pageerase --region @userdata --ip "${BED_HOST[i]}"

    # Lockbits is needed in Series 1 only
    # commander device pageerase --region @lockbits  --ip "${BED_HOST[i]}"
  done
}

if [ ! -f "${script_folder}/conf" ]; then
  echo "Error: conf file not found in $script_folder" >&2
  exit 1
fi
if [ ! -f "${script_folder}/utils.sh" ]; then
  echo "Error: utils.sh not found in $script_folder" >&2
  exit 1
fi

source "${script_folder}/conf"
source "${script_folder}/utils.sh"

for tool in commander dos2unix; do
  if ! command -v $tool >/dev/null 2>&1; then
    echo "Error: $tool is not installed." >&2
    exit 1
  fi
done

vars=(artifacts BED_TSV REGION)
for v in "${vars[@]}"; do
  if [ -z "${!v}" ]; then
    echo "Error: Required variable $v is not set in conf." >&2
    exit 1
  fi
done

bed_load "${BED_TSV}"

for ((i = 0; i < BED_N; i++)); do
  firmwares=("${BED_FIRMWARE[i]}")
  [ -n "${BED_BOOTLOADER[i]}" ] && firmwares=("${BED_BOOTLOADER[i]}" "${firmwares[@]}")
  for firmware in "${firmwares[@]}"; do
    if [ ! -f "${script_folder}/${artifacts}/${firmware}" ]; then
      echo "Error: Missing firmware artifact: ${script_folder}/${artifacts}/${firmware}" >&2
      echo "Run ./endurance_test/01_fetch_artifacts.sh or place artifacts manually under ${script_folder}/${artifacts}" >&2
      exit 1
    fi
  done
done

cleanup_boards

echo "dsks=(" > "${script_folder}/${artifacts}/dsks"
for ((i = 0; i < BED_N; i++)); do
  echo
  echo "=========================================="
  echo
  echo "dut_$i: ${BED_HOST[i]}"

  addr="${BED_HOST[i]}"
  device="${BED_DEVICE[i]}"
  firmware="${script_folder}/${artifacts}/${BED_FIRMWARE[i]}"

  commander device info --device "${device}" --ip "$addr"
  sleep 0.5
  if [ -n "${BED_BOOTLOADER[i]}" ]; then
    bootloader="${script_folder}/${artifacts}/${BED_BOOTLOADER[i]}"
    commander flash "${bootloader}" --device "${device}" --ip "$addr"
    sleep 0.5
  fi
  commander flash "${firmware}" --device "${device}" --ip "$addr"
  sleep 0.5
  commander flash --tokengroup znet --token MFG_ZWAVE_COUNTRY_FREQ:$REGION --device "${device}" --ip "$addr"
  sleep 1

  dsk=$(commander --apack device zwave-qrcode --timeout 2000 --tif swd --device "${device}" --ip "$addr")
  dsk=$(echo "$dsk" | grep -o 'INFO: QR code: .*')
  dsk=$(echo "$dsk" | sed -e 's|.*: ............\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\).*]|\1-\2-\3-\4-\5-\6-\7-\8|g')
  echo "$dsk" >> "${artifacts}/dsks"
  echo
  power_off_board "$addr"
  echo "=========================================="
done
echo ")" >> "${artifacts}/dsks"

dos2unix "${artifacts}/dsks"
