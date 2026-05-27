#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -e

script_folder=$(dirname "$0")
source "${script_folder}/conf"
source "${script_folder}/utils.sh"
source "${script_folder}/${artifacts}/dsks"

bed_load "${BED_TSV}"

mkdir -p "${logs_dir}"

launch_reference_client

# Walk end-device slots in declaration order; dsks[count] is the DSK for
# the count-th end device (zniffer/controller emit empty QR output which
# the array literal silently drops). Long Range regions (US-LR 0x09,
# EU-LR 0x0B) need bootmode:2 so ZGW includes the node on the LR channel
# instead of the classic mesh; everything else stays on bootmode:1.
declare -i count=0
for slot in $(bed_iter_end_devices); do
	region="${BED_REGION[slot]:-${REGION}}"
	case "${region}" in
		0x09|0x0B|0x0b) bootmode=2 ;;
		*)              bootmode=1 ;;
	esac
	echo "pl_add ${dsks[count]} name:dut-${count} location:${LOCATION} bootmode:${bootmode} smartstart:2" >&3
	sleep 1
	count+=1
done

clean_exit
