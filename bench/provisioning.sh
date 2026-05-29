#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages provision_on_host.sh + utils.sh + conf + dsks on [zgw-host]
# 2. Runs the worker over SSH
# 3. Pulls back logs to ${STEP_DIR} on [test-controller].
#
# Required env (set by the tests/<name>/04_provisioning.sh wrapper):
#   TEST_DIR          path to the test dir (conf + bed.tsv)
#   RUN_DIR           run root on [test-controller]
#   RUN_REMOTE_DIR    run root on [zgw-host]
#   STEP_DIR          ${RUN_DIR}/04_provisioning
#   STEP_REMOTE_DIR   ${RUN_REMOTE_DIR}/04_provisioning
#
# Prerequisites on [zgw-host]:
# - SSH key-based access for ${ZGW_USER}
# - ZGW already installed and running (step 03 done)
# - reference_client present at ${ZGW_STAGE_DIR}/reference_client

set -euo pipefail

script_folder=$(dirname "$0")

if [ -z "${TEST_DIR:-}" ]; then
  echo "Error: TEST_DIR is not set." >&2
  echo "       call this script from a tests/<name>/ wrapper." >&2
  exit 1
fi
if [ ! -f "${TEST_DIR}/conf" ]; then
  echo "Error: conf file not found in ${TEST_DIR}" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${TEST_DIR}/conf"

vars=(ZGW_HOST ZGW_USER ZGW_STAGE_DIR LOCATION ARTIFACTS_DIR REFERENCE_CLIENT)
for v in "${vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: required variable ${v} not set in conf." >&2
    exit 1
  fi
done

run_vars=(RUN_DIR RUN_REMOTE_DIR STEP_DIR STEP_REMOTE_DIR)
for v in "${run_vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: ${v} must be set (tests/<name>/04_provisioning.sh)." >&2
    exit 1
  fi
done

if [ ! -f "${ARTIFACTS_DIR}/dsks" ]; then
  echo "Error: ${ARTIFACTS_DIR}/dsks not found." >&2
  echo "       run 02_prepare_boards.sh first." >&2
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
  echo "       run 03_setup_zipgateway.sh first." >&2
  exit 1
fi

echo "Staging provisioning files on ${ZGW_HOST}:${ZGW_STAGE_DIR} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" \
  "mkdir -p '${ZGW_STAGE_DIR}/artifacts' '${STEP_REMOTE_DIR}'"
rsync -a \
  "${script_folder}/provision_on_host.sh" \
  "${script_folder}/utils.sh" \
  "${TEST_DIR}/bed.tsv" \
  "${TEST_DIR}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"
rsync -a \
  "${ARTIFACTS_DIR}/dsks" \
  "${ssh_target}:${ZGW_STAGE_DIR}/artifacts/"

echo "Running provision_on_host.sh on ${ZGW_HOST} (logs -> ${STEP_REMOTE_DIR}) ..."
ssh "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo RUN_DIR='${RUN_REMOTE_DIR}' bash provision_on_host.sh"

echo "Pulling logs back to ${STEP_DIR}/ ..."
mkdir -p "${STEP_DIR}"
rsync -a \
  "${ssh_target}:${STEP_REMOTE_DIR}/" \
  "${STEP_DIR}/"

echo "Provisioning complete."
