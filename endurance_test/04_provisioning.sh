#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -e

script_folder=$(dirname "$0")
source dsks
source "${script_folder}/conf"
source "${script_folder}/utils.sh"

launch_reference_client $ZGW_STAGE_DIR/reference_client

declare -i count=0
for device in "${dsks[@]}"; do
	echo "pl_add ${device} name:dut-${count} location:${LOCATION} bootmode:1 smartstart:2" >&3
  sleep 1
	count+=1
done

clean_exit
