#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages provision_on_host.sh + utils.sh + conf + dsks on [zgw-host]
# 2. Runs the script over SSH
# 3. Pulls back the logs.
#
# Prerequisites on [zgw-host]:
# - SSH key-based access for ${ZGW_USER}
# - ZGW already installed and running (step 03 done)
# - reference_client present at ${ZGW_STAGE_DIR}/reference_client

set -euo pipefail

script_folder=$(dirname "$0")

if [ ! -f "${script_folder}/conf" ]; then
  echo "Error: conf file not found in ${script_folder}" >&2
  exit 1
fi
source "${script_folder}/conf"

vars=(ZGW_HOST ZGW_USER ZGW_STAGE_DIR LOCATION artifacts logs_dir REFERENCE_CLIENT)
for v in "${vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: required variable ${v} not set in conf." >&2
    exit 1
  fi
done

if [ ! -f "${script_folder}/${artifacts}/dsks" ]; then
  echo "Error: ${script_folder}/${artifacts}/dsks not found." >&2
  echo "       run ./02_prepare_boards.sh first." >&2
  exit 1
fi

ssh_target="${ZGW_USER}@${ZGW_HOST}"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)

echo "Probing SSH to ${ssh_target} ..."
if ! ssh "${ssh_opts[@]}" "${ssh_target}" true; then
  echo "Error: cannot SSH non-interactively to ${ssh_target}." >&2
  echo "       configure key-based auth + passwordless sudo first." >&2
  exit 1
fi

echo "Checking reference_client at ${REFERENCE_CLIENT} ..."
if ! ssh "${ssh_opts[@]}" "${ssh_target}" \
    "test -x '${REFERENCE_CLIENT}'"; then
  echo "Error: ${REFERENCE_CLIENT} missing or not executable on ${ZGW_HOST}." >&2
  echo "       run ./03_setup_zipgateway.sh first." >&2
  exit 1
fi

echo "Staging provisioning files on ${ZGW_HOST}:${ZGW_STAGE_DIR} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" \
  "mkdir -p '${ZGW_STAGE_DIR}/${artifacts}'"
rsync -a \
  "${script_folder}/provision_on_host.sh" \
  "${script_folder}/utils.sh" \
  "${script_folder}/bed.tsv" \
  "${script_folder}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"
rsync -a \
  "${script_folder}/${artifacts}/dsks" \
  "${ssh_target}:${ZGW_STAGE_DIR}/${artifacts}/"

echo "Running provision_on_host.sh on ${ZGW_HOST} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo bash provision_on_host.sh"

echo "Pulling logs back to ${script_folder}/${logs_dir}/ ..."
mkdir -p "${script_folder}/${logs_dir}"
ssh "${ssh_opts[@]}" "${ssh_target}" \
  "mkdir -p '${ZGW_STAGE_DIR}/${logs_dir}'"
rsync -a \
  "${ssh_target}:${ZGW_STAGE_DIR}/${logs_dir}/" \
  "${script_folder}/${logs_dir}/"

echo "Provisioning complete."
