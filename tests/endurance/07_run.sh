#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages run_on_host.sh + utils.sh + conf + bed.tsv on [zgw-host]
# 2. Detects HomeID once from the ZGW log on [zgw-host]
# 3. Starts the ST-01 heartbeat probe locally (checks/st01_heartbeat.sh),
#    sampling ZGW liveness into ${STEP_DIR} while the load runs
# 4. Runs the stress burst loop over SSH with a PTY (so CTRL+C reaches
#    the worker)
# 5. Stops the heartbeat, pulls back ${STEP_REMOTE_DIR}/, then runs the
#    analyzer (checks/st01_analyze.sh) which scans ${RUN_DIR} and writes
#    verdict.txt + summary.json at the run root.
#
# The driver's own exit code mirrors the analyzer verdict
# (0=PASS, 1=FAIL, 2=INCONCLUSIVE) so CI / callers can gate on it.
#
# Prerequisites on [zgw-host]:
# - SSH key-based access for ${ZGW_USER}, passwordless sudo
# - ZGW running and devices provisioned (steps 03 + 04 done)
# Prerequisite on [test-controller]: avahi-resolve (avahi-utils).

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <run_dir>" >&2
  echo "       run ./00_init_test_run.sh first." >&2
  exit 2
fi

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

run_dir_attach "$1"
STEP_NAME="07_run"
STEP_DIR="${RUN_DIR}/${STEP_NAME}"
STEP_REMOTE_DIR="${RUN_REMOTE_DIR}/${STEP_NAME}"
mkdir -p "${STEP_DIR}"
echo "Run output: ${STEP_DIR}"

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

echo "Detecting HomeID from ${ssh_target} ..."
homeid_raw="$(ssh "${ssh_opts[@]}" "${ssh_target}" \
  "tac /var/log/zipgateway.log | grep -m1 HomeID 2>/dev/null | cut -f4 -d' '" || true)"
homeid_raw="${homeid_raw//[![:alnum:]]/}"
homeid="$(echo "${homeid_raw}" | tr '[:lower:]' '[:upper:]')"
if [[ ! "${homeid}" =~ ^[0-9A-F]{8}$ ]]; then
  echo "Error: could not detect a valid 8-hex HomeID from /var/log/zipgateway.log." >&2
  echo "       detected='${homeid_raw}'" >&2
  exit 1
fi
echo "Detected HomeID: ${homeid}"
printf "%s\n" "${homeid}" > "${STEP_DIR}/st01_homeid.txt"

echo "Staging run_on_host.sh on ${ZGW_HOST}:${ZGW_STAGE_DIR} ..."
ssh "${ssh_opts[@]}" "${ssh_target}" "mkdir -p '${ZGW_STAGE_DIR}' '${STEP_REMOTE_DIR}'"
rsync -a \
  "${TEST_DIR}/run_on_host.sh" \
  "${BENCH_DIR}/utils.sh" \
  "${TEST_DIR}/bed.tsv" \
  "${TEST_DIR}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"

# Start the ST-01 heartbeat probe locally (samples while the load runs)
heartbeat_csv="${STEP_DIR}/st01_heartbeat.csv"
heartbeat_pid=""
echo "Starting ST-01 heartbeat probe -> ${heartbeat_csv} ..."
"${TEST_DIR}/checks/st01_heartbeat.sh" \
  --out "${heartbeat_csv}" \
  --homeid "${homeid}" \
  --cadence-s "${HEARTBEAT_CADENCE_S:-10}" \
  --timeout-s "${HEARTBEAT_TIMEOUT_S:-5}" &
heartbeat_pid=$!

stop_heartbeat() {
  if [ -n "${heartbeat_pid}" ] && kill -0 "${heartbeat_pid}" 2>/dev/null; then
    echo "Stopping heartbeat probe (pid ${heartbeat_pid}) ..."
    kill -TERM "${heartbeat_pid}" 2>/dev/null || true
    wait "${heartbeat_pid}" 2>/dev/null || true
  fi
}
trap stop_heartbeat EXIT

echo "Running run_on_host.sh on ${ZGW_HOST} (CTRL+C to stop) ..."
# -tt forces a PTY so CTRL+C from this terminal reaches the worker.
# Always pull logs back, even if the SSH session ends with a signal.
ssh -tt "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo RUN_DIR='${RUN_REMOTE_DIR}' bash run_on_host.sh" || true

stop_heartbeat
trap - EXIT

echo "Pulling logs back to ${STEP_DIR}/ ..."
rsync -a \
  "${ssh_target}:${STEP_REMOTE_DIR}/" \
  "${STEP_DIR}/"

echo "Analyzing run -> verdict ..."
analyzer_code=0
"${TEST_DIR}/checks/st01_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || analyzer_code=$?

echo "Run complete. Verdict artifacts in ${RUN_DIR}/ (verdict.txt, summary.json)."
exit "${analyzer_code}"
