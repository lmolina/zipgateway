#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -e

script_folder=$(dirname "$0")
source "${script_folder}/conf"
if [ -z "${RUN_LOGS_DIR:-}" ]; then
  echo "Error: RUN_LOGS_DIR is not set." >&2
  exit 1
fi
logs_dir="${RUN_LOGS_DIR}"
source "${script_folder}/utils.sh"
source "${script_folder}/artifacts/dsks"

bed_load "${BED_TSV}"

mkdir -p "${logs_dir}"

launch_reference_client

provisioning_log="${logs_dir}/provisioning_pl_add.log"
: > "${provisioning_log}"

# dsks[i] is the DSK for bed slot i (including zniffer/controller rows from
# prepare_boards.sh).
for slot in $(bed_iter_end_devices); do
	region="${BED_REGION[slot]:-${REGION}}"
	case "${region}" in
		0x09|0x0B|0x0b) bootmode=2 ;;
		*)              bootmode=1 ;;
	esac
	line="pl_add ${dsks[slot]} name:dut-${slot} location:${LOCATION} bootmode:${bootmode} smartstart:2"
	echo "${line}" >> "${provisioning_log}"
	echo "${line}" >&3
	sleep 1
done

clean_exit
