#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Run from [test-controller]:
# 1. Stages run_on_host.sh + utils.sh + conf + bed.tsv on [zgw-host]
# 2. Detects HomeID once from the ZGW log on [zgw-host]
# 3. Starts probes locally (checks/),
# 4. Runs the stress burst loop over SSH
# 5. Stops the probes, pulls back ${STEP_REMOTE_DIR}/, then runs all
#    per-test analyzers and writes per-test verdict + summary files
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

# shellcheck source=/dev/null
source "${TEST_DIR}/conf"
# shellcheck source=/dev/null
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
# shellcheck disable=SC2029
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
# shellcheck disable=SC2029
ssh "${ssh_opts[@]}" "${ssh_target}" "mkdir -p '${ZGW_STAGE_DIR}' '${ZGW_STAGE_DIR}/checks' '${STEP_REMOTE_DIR}'"
rsync -a \
  "${TEST_DIR}/run_on_host.sh" \
  "${BENCH_DIR}/utils.sh" \
  "${TEST_DIR}/bed.tsv" \
  "${TEST_DIR}/conf" \
  "${ssh_target}:${ZGW_STAGE_DIR}/"
rsync -a \
  "${TEST_DIR}/checks/st04_process_sampler.sh" \
  "${ssh_target}:${ZGW_STAGE_DIR}/checks/"

heartbeat_csv="${STEP_DIR}/st01_heartbeat.csv"
heartbeat_pid=""
echo "Starting ST-01 heartbeat probe -> ${heartbeat_csv} ..."
"${TEST_DIR}/checks/st01_heartbeat.sh" \
  --out "${heartbeat_csv}" \
  --homeid "${homeid}" \
  --cadence-s "${HEARTBEAT_CADENCE_S:-10}" \
  --timeout-s "${HEARTBEAT_TIMEOUT_S:-5}" &
heartbeat_pid=$!

tailer_csv="${STEP_DIR}/st02_events.csv"
tailer_pid=""
echo "Starting ST-02 false-dead tailer -> ${tailer_csv} ..."
# setsid: stop_probes can signal the whole session (ssh tail, grep, probes).
setsid "${TEST_DIR}/checks/st02_tailer.sh" \
  --out "${tailer_csv}" \
  --homeid "${homeid}" \
  --ssh-target "${ssh_target}" \
  --event-re "${ST02_EVENT_RE:-Node [0-9]+ is now failing}" \
  --nodeid-re "${ST02_NODEID_RE:-Node [0-9]+}" \
  --resolve-timeout-s "${ST02_RESOLVE_TIMEOUT_S:-5}" \
  --probe-timeout-s "${ST02_PROBE_TIMEOUT_S:-30}" \
  --settle-s "${ST02_SETTLE_S:-1}" &
tailer_pid=$!

st03_probe_csv="${STEP_DIR}/st03_zgw_probe.csv"
st03_probe_pid=""
echo "Starting ST-03 ZGW probe -> ${st03_probe_csv} ..."
"${TEST_DIR}/checks/st03_zgw_probe.sh" \
  --out "${st03_probe_csv}" \
  --homeid "${homeid}" \
  --cadence-s "${ZIP_PROBE_CADENCE_S:-30}" \
  --timeout-s "${ZIP_PROBE_TIMEOUT_S:-5}" &
st03_probe_pid=$!

wait_pid() {
  local pid="$1"
  local max_s="${2:-8}"
  local i=0
  while [ "${i}" -lt "${max_s}" ] && kill -0 "${pid}" 2>/dev/null; do
    sleep 1
    i=$((i + 1))
  done
  if kill -0 "${pid}" 2>/dev/null; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
  wait "${pid}" 2>/dev/null || true
}

probes_stopped=0
stop_probes() {
  [ "${probes_stopped}" -eq 1 ] && return
  probes_stopped=1

  if [ -n "${heartbeat_pid}" ] && kill -0 "${heartbeat_pid}" 2>/dev/null; then
    echo "Stopping ST-01: heartbeat probe (pid ${heartbeat_pid}) ..."
    kill -TERM "${heartbeat_pid}" 2>/dev/null || true
    wait_pid "${heartbeat_pid}" 5
  fi
  if [ -n "${tailer_pid}" ] && kill -0 "${tailer_pid}" 2>/dev/null; then
    echo "Stopping ST-02: false-dead tailer (pid ${tailer_pid}) ..."
    kill -TERM -"${tailer_pid}" 2>/dev/null || true
    wait_pid "${tailer_pid}" 5
  fi
  if [ -n "${st03_probe_pid}" ] && kill -0 "${st03_probe_pid}" 2>/dev/null; then
    echo "Stopping ST-03: ZGW probe (pid ${st03_probe_pid}) ..."
    kill -TERM "${st03_probe_pid}" 2>/dev/null || true
    wait_pid "${st03_probe_pid}" 5
  fi
}
trap stop_probes EXIT

echo "Running run_on_host.sh on ${ZGW_HOST} (CTRL+C to stop) ..."
# -tt forces a PTY so CTRL+C from this terminal reaches the worker.
# Always pull logs back, even if the SSH session ends with a signal.
ssh -tt "${ssh_opts[@]}" "${ssh_target}" \
  "cd '${ZGW_STAGE_DIR}' && sudo RUN_DIR='${RUN_REMOTE_DIR}' bash run_on_host.sh" || true

stop_probes
trap - EXIT

echo "Pulling logs back to ${STEP_DIR}/ ..."
rsync -a \
  "${ssh_target}:${STEP_REMOTE_DIR}/" \
  "${STEP_DIR}/"

echo "Analyzing run -> ST-01 verdict ..."
st01_code=0
"${TEST_DIR}/checks/st01_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || st01_code=$?

echo "Analyzing run -> ST-02 verdict ..."
st02_code=0
"${TEST_DIR}/checks/st02_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || st02_code=$?

echo "Analyzing run -> ST-03 verdict ..."
st03_code=0
"${TEST_DIR}/checks/st03_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || st03_code=$?

echo "Analyzing run -> ST-04 verdict ..."
st04_code=0
"${TEST_DIR}/checks/st04_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || st04_code=$?
echo "Analyzing run -> ST-05 verdict ..."
st05_code=0
"${TEST_DIR}/checks/st05_analyze.sh" --run-dir "${RUN_DIR}" --conf "${TEST_DIR}/conf" \
  || st05_code=$?
run_code="${st01_code}"
[ "${st02_code}" -gt "${run_code}" ] && run_code="${st02_code}"
[ "${st03_code}" -gt "${run_code}" ] && run_code="${st03_code}"
[ "${st04_code}" -gt "${run_code}" ] && run_code="${st04_code}"
[ "${st05_code}" -gt "${run_code}" ] && run_code="${st05_code}"

echo "Run complete. Verdict artifacts in ${RUN_DIR}/:"
echo "  ST-01: verdict.txt, summary.json (exit ${st01_code})"
echo "  ST-02: st02_verdict.txt, st02_summary.json (exit ${st02_code})"
echo "  ST-03: st03_verdict.txt, st03_summary.json (exit ${st03_code})"
echo "  ST-04: st04_verdict.txt, st04_summary.json (exit ${st04_code})"
echo "  ST-05: st05_verdict.txt, st05_summary.json (exit ${st05_code})"
exit "${run_code}"
