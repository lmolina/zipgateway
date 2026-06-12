#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Simulate end-user interactions with bench devices from [test-controller].
# Launched in the background by 07_run.sh while the endurance load runs.

set -euo pipefail

DEVICE_TRAFFIC_INTERVAL_S=$((15 * 60))

mydir=$(cd "$(dirname "$0")" && pwd)
BENCH_DIR="$(cd "${mydir}/../../bench" && pwd)"

# shellcheck source=conf
source "${mydir}/conf"
# shellcheck source=../../bench/utils.sh
source "${BENCH_DIR}/utils.sh"

bed_load "${BED_TSV}"

running=1
stop() {
  running=0
}
trap stop TERM INT

sleep_interruptible() {
  local remaining="$1"
  while [ "${remaining}" -gt 0 ] && [ "${running}" -eq 1 ]; do
    sleep 1
    remaining=$((remaining - 1))
  done
}

wait_before_start="$1"
if [ "${wait_before_start}" -ne 0 ]; then
  sleep "${wait_before_start}"
fi

iter=0
while [ "${running}" -eq 1 ]; do
  if [ $((iter % 2)) -eq 0 ]; then
    for slot in $(bed_iter_end_devices); do
      host="${BED_HOST[slot]}"
      role="${BED_ROLE[slot]}"
      case "${role}" in
        switch)
          echo "$(date -Is) toggle slot=${slot} host=${host} ${role}"
          board_cli "${host}" "toggle_led"
          sleep 1
          ;;
        door_lock)
          echo "$(date -Is) toggle slot=${slot} host=${host} ${role}"
          board_cli "${host}" "button press 0 0"
          sleep 1
          ;;
        *) ;;
      esac
    done
  else
    # All in parallel
    pids=()
    for slot in $(bed_iter_end_devices); do
      host="${BED_HOST[slot]}"
      role="${BED_ROLE[slot]}"
      case "${role}" in
        switch)
          echo "$(date -Is) toggle slot=${slot} host=${host} ${role}"
          board_cli "${host}" "toggle_led" &
          pids+=("$!")
          ;;
        door_lock)
          echo "$(date -Is) toggle slot=${slot} host=${host} ${role}"
          board_cli "${host}" "button press 0 0" &
          pids+=("$!")
          ;;
        *) ;;
      esac
    done

    parallel_failures=0
    for pid in "${pids[@]}"; do
      if ! wait "${pid}"; then
        parallel_failures=$((parallel_failures + 1))
      fi
    done
    if [ "${parallel_failures}" -gt 0 ]; then
      echo "$(date -Is) parallel trigger failures=${parallel_failures}" >&2
    fi
  fi
  iter=$((iter + 1))
  sleep_interruptible "${DEVICE_TRAFFIC_INTERVAL_S}"
done

echo "$(date -Is) device_traffic stopped"
