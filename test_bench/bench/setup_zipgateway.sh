#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages the ZGW .deb plus zgw_cleanup.sh on [zgw-host] over rsync
# 2. Runs the cleanup
# 3. reinstall the ZGW
# 4. reboots the RPi
#
# the host blocks until SSH is reachable again or the timeout
# expires.
#
# Prerequisites on [zgw-host]:
# - SSH key-based access for ${ZGW_USER}
# - Passwordless sudo for ${ZGW_USER}.
# ${ZGW_USER} is pi by default

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
source "${TEST_DIR}/conf"

vars=(ZGW_HOST ZGW_USER ZGW_STAGE_DIR ZGW_REBOOT_WAIT_SEC ZIP_GATEWAY LIBZWAVEIP ARTIFACTS_DIR)
for v in "${vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: required variable ${v} not set in conf." >&2
    exit 1
  fi
done

ssh_target="${ZGW_USER}@${ZGW_HOST}"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)

echo "Probing SSH to ${ssh_target} ..."
if ! ssh "${ssh_opts[@]}" "${ssh_target}" true; then
  echo "Error: cannot SSH non-interactively to ${ssh_target}." >&2
  echo "       configure key-based auth + passwordless sudo first." >&2
  exit 1
fi

echo "Staging files on ${ZGW_HOST}:${ZGW_STAGE_DIR} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" "mkdir -p '${ZGW_STAGE_DIR}'"
rsync -a \
  "${ARTIFACTS_DIR}/${ZIP_GATEWAY}" \
  "${ARTIFACTS_DIR}/${LIBZWAVEIP}" \
  "${script_folder}/zgw_cleanup.sh" \
  "${TEST_DIR}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"

echo "Running zgw_cleanup.sh on ${ZGW_HOST} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" "sudo bash '${ZGW_STAGE_DIR}/zgw_cleanup.sh'"

echo "Rebooting ${ZGW_HOST} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" "sudo reboot" || true

deadline=$(( $(date +%s) + ZGW_REBOOT_WAIT_SEC ))
sleep 5
while [ "$(date +%s)" -lt "${deadline}" ]; do
  if ssh "${ssh_opts[@]}" "${ssh_target}" true 2>/dev/null; then
    echo "[zgw-host] back up."
    exit 0
  fi
  sleep 5
done

echo "Warning: ${ZGW_HOST} did not come back within ${ZGW_REBOOT_WAIT_SEC}s." >&2
exit 2
