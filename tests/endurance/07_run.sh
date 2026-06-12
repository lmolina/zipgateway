#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages run_on_host.sh + utils.sh + conf + bed.tsv on [zgw-host]
# 2. Detects HomeID once from the ZGW log on [zgw-host]
# 3. Starts the ET-01 heartbeat probe locally (checks/st01_heartbeat.sh),
#    sampling ZGW liveness into ${STEP_DIR} while the load runs
# 4. Starts device_traffic.sh locally to simulate end-user board interactions
# 5. Runs the endurance burst loop over SSH with a PTY (so CTRL+C reaches
#    the worker)
# 6. Stops background probes, pulls back ${STEP_REMOTE_DIR}/, then runs the
#    ET-01 analyzer (checks/st01_analyze.sh) which scans ${RUN_DIR} and writes
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

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
export TEST_DIR
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
exec > >(tee -a "${STEP_DIR}/console.log") 2>&1
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

# Start the ET-01 heartbeat probe locally (samples while the load runs)
heartbeat_csv="${STEP_DIR}/st01_heartbeat.csv"
heartbeat_pid=""
echo "Starting ET-01 heartbeat probe -> ${heartbeat_csv} ..."
bash "${TEST_DIR}/checks/st01_heartbeat.sh" \
  --out "${heartbeat_csv}" \
  --homeid "${homeid}" \
  --cadence-s "${HEARTBEAT_CADENCE_S:-10}" \
  --timeout-s "${HEARTBEAT_TIMEOUT_S:-5}" &
heartbeat_pid=$!

device_traffic_log="${STEP_DIR}/device_traffic.log"
device_traffic_pid=""
echo "Starting device traffic -> ${device_traffic_log} ..."

# Give the run_on_host.sh some time before generating traffic from devices
bash "${TEST_DIR}/device_traffic.sh" 120 >> "${device_traffic_log}" 2>&1 &
device_traffic_pid=$!

stop_background_workers() {
  if [ -n "${heartbeat_pid}" ] && kill -0 "${heartbeat_pid}" 2>/dev/null; then
    echo "Stopping heartbeat probe (pid ${heartbeat_pid}) ..."
    kill -TERM "${heartbeat_pid}" 2>/dev/null || true
    wait "${heartbeat_pid}" 2>/dev/null || true
  fi
  if [ -n "${device_traffic_pid}" ] && kill -0 "${device_traffic_pid}" 2>/dev/null; then
    echo "Stopping device traffic (pid ${device_traffic_pid}) ..."
    kill -TERM "${device_traffic_pid}" 2>/dev/null || true
    wait "${device_traffic_pid}" 2>/dev/null || true
  fi
}
trap stop_background_workers EXIT

echo "Running run_on_host.sh on ${ZGW_HOST} (CTRL+C to stop) ..."
# -tt forces a PTY so CTRL+C from this terminal reaches the worker.
# Always pull logs back, even if the SSH session ends with a signal.
ssh -tt "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo RUN_DIR='${RUN_REMOTE_DIR}' bash run_on_host.sh" || true

stop_background_workers
trap - EXIT

echo "Pulling logs back to ${STEP_DIR}/ ..."
rsync -a \
  "${ssh_target}:${STEP_REMOTE_DIR}/" \
  "${STEP_DIR}/"

echo "Analyzing run -> ET-01 verdict ..."
analyzer_code=0
bash "${TEST_DIR}/checks/st01_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || analyzer_code=$?

echo "Run complete. ET-01 verdict artifacts in ${RUN_DIR}/ (verdict.txt, summary.json)."
exit "${analyzer_code}"
