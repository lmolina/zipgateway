#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages run_on_host.sh + utils.sh + conf on [zgw-host]
# 2. Runs the burst loop over SSH with a PTY (so CTRL+C reaches the worker)
# 3. Pulls back run_<UTC>/ once the worker stops.
#
# Prerequisites on [zgw-host]:
# - SSH key-based access for ${ZGW_USER}, passwordless sudo
# - ZGW running and devices provisioned (steps 03 + 04 done)

set -euo pipefail

export TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "${TEST_DIR}/../../bench" && pwd)"

if [ ! -f "${TEST_DIR}/conf" ]; then
  echo "Error: conf file not found in ${TEST_DIR}" >&2
  exit 1
fi
# shellcheck source=conf
source "${TEST_DIR}/conf"
# shellcheck source=../../bench/utils.sh
source "${BENCH_DIR}/utils.sh"

vars=(ZGW_HOST ZGW_USER ZGW_STAGE_DIR LOCATION REFERENCE_CLIENT TEST_DURATION)
for v in "${vars[@]}"; do
  if [ -z "${!v:-}" ]; then
    echo "Error: required variable ${v} not set in conf." >&2
    exit 1
  fi
done

if ! duration_to_seconds "${TEST_DURATION}" >/dev/null; then
  echo "Error: TEST_DURATION='${TEST_DURATION}' is not a valid duration." >&2
  echo "       expected <integer>[s|m|h|d] (e.g. 72h, 30m, 259200)." >&2
  exit 1
fi

run_dir_init "${TEST_DIR}"
echo "Run output: ${RUN_DIR}"

ssh_target="${ZGW_USER}@${ZGW_HOST}"
ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5)

echo "Probing SSH to ${ssh_target} ..."
if ! ssh "${ssh_opts[@]}" "${ssh_target}" true; then
  echo "Error: cannot SSH non-interactively to ${ssh_target}." >&2
  exit 1
fi

echo "Checking reference_client at ${REFERENCE_CLIENT} ..."
if ! ssh "${ssh_opts[@]}" "${ssh_target}" \
    "test -x '${REFERENCE_CLIENT}'"; then
  echo "Error: ${REFERENCE_CLIENT} missing on ${ZGW_HOST}." >&2
  echo "       run ./03_setup_zipgateway.sh first." >&2
  exit 1
fi

echo "Staging run_on_host.sh on ${ZGW_HOST}:${ZGW_STAGE_DIR} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" "mkdir -p '${ZGW_STAGE_DIR}' '${RUN_REMOTE_DIR}'"
rsync -a \
  "${TEST_DIR}/run_on_host.sh" \
  "${BENCH_DIR}/utils.sh" \
  "${TEST_DIR}/bed.tsv" \
  "${TEST_DIR}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"

echo "Running run_on_host.sh on ${ZGW_HOST} (CTRL+C to stop) ..."
# -tt forces a PTY so CTRL+C from this terminal reaches the worker.
# Always pull logs back, even if the SSH session ends with a signal.
ssh -tt "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo RUN_LOGS_DIR='${RUN_REMOTE_DIR}' bash run_on_host.sh" || true

echo "Pulling logs back to ${RUN_DIR}/ ..."
rsync -a \
  "${ssh_target}:${RUN_REMOTE_DIR}/" \
  "${RUN_DIR}/"

echo "Run complete."
