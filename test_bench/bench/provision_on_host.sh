#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Worker for step 04 (SmartStart provisioning) on [zgw-host].
# Invoked by bench/provisioning.sh over SSH with RUN_DIR pointing at
# the run root on [zgw-host].
set -e

script_folder=$(dirname "$0")
source "${script_folder}/conf"
if [ -z "${RUN_DIR:-}" ]; then
  echo "Error: RUN_DIR is not set." >&2
  exit 1
fi
STEP_DIR="${RUN_DIR}/04_provisioning"
export STEP_DIR
source "${script_folder}/utils.sh"
source "${script_folder}/artifacts/dsks"

bed_load "${BED_TSV}"

mkdir -p "${STEP_DIR}"

launch_reference_client

provisioning_log="${STEP_DIR}/provisioning_pl_add.log"
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
