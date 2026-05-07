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
  for i in $(seq 0 $((${#ADDR[@]} - 1)));
  do
    echo
    echo "=========================================="
    echo "dut_$i: ${ADDR[$i]}"

    addr=${ADDR[$i]}

     # Some firmware version may break the radio board, thus the need for a
     # recover
     commander device recover --ip "${addr}"

     commander device masserase --ip "${addr}"
     commander device pageerase --region @userdata  --ip "${addr}"

     # Lockbits is needed in Series 1 only
     # commander device pageerase --region @lockbits  --ip "${addr}"
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

vars=(artifacts ADDR DEVICE HEX_1 HEX_2 REGION)
for v in "${vars[@]}"; do
  if [ -z "${!v}" ]; then
    echo "Error: Required variable $v is not set in conf." >&2
    exit 1
  fi
done

for firmware in "${HEX_1[@]}" "${HEX_2[@]}"; do
  if [ ! -f "${script_folder}/${firmware}" ]; then
    echo "Error: Missing firmware artifact: ${script_folder}/${firmware}" >&2
    echo "Run ./endurance_test/01_fetch_artifacts.sh or place artifacts manually under ${script_folder}/${artifacts}" >&2
    exit 1
  fi
done

cleanup_boards

echo "dsks=(" > dsks
for i in $(seq 0 $((${#ADDR[@]} - 1)));
do
  echo
  echo "=========================================="
  echo
  echo "dut_$i: ${ADDR[$i]}"

  addr=${ADDR[$i]}

  commander device info --device "${DEVICE[${i}]}" --ip "$addr"
  sleep 0.5
  commander flash "$script_folder/${HEX_1[${i}]}" --device "${DEVICE[${i}]}" --ip "$addr"
  sleep 0.5
  commander flash "$script_folder/${HEX_2[${i}]}" --device "${DEVICE[${i}]}" --ip "$addr"
  sleep 0.5
  commander flash --tokengroup znet --token MFG_ZWAVE_COUNTRY_FREQ:$REGION --device "${DEVICE[${i}]}" --ip "$addr"
  sleep 1

  dsk=$(commander --apack device zwave-qrcode --timeout 2000 --tif swd --device "${DEVICE[${i}]}" --ip "$addr")
  dsk=$(echo "$dsk" | grep -o 'INFO: QR code: .*')
  dsk=$(echo "$dsk" | sed -e 's|.*: ............\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\)\(.....\).*]|\1-\2-\3-\4-\5-\6-\7-\8|g')
  echo "$dsk" >> "${artifacts}/dsks"
  echo
  power_off_board "$addr"
  echo "=========================================="
done
echo ")" >> "${artifacts}/dsks"

dos2unix "${artifacts}/dsks"
