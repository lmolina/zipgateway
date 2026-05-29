#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Endurance burst loop for ST-01 (NCP tx-queue lockup). Runs on [zgw-host],
# staged and invoked by 07_run.sh.

set -euo pipefail
shopt -s nullglob

mydir=$(dirname "$0")
source "${mydir}/conf"
if [ -z "${RUN_DIR:-}" ]; then
  echo "Error: RUN_DIR is not set." >&2
  exit 1
fi
STEP_DIR="${RUN_DIR}/07_run"
export STEP_DIR
source "${mydir}/utils.sh"

bed_load "${BED_TSV}"

mkdir -p "${STEP_DIR}"
trap clean_exit SIGINT
trap launch_reference_client SIGCHLD

sudo /etc/init.d/zipgateway stop
sleep 10
backups="/var/log/zipgateway-$(date +%Y%m%dT%H%M%S).old"
sudo mkdir -p "${backups}"
log_backups=( /var/log/ziprouter.serlog* /var/log/zipgateway.log* )
if [ "${#log_backups[@]}" -gt 0 ]; then
  sudo mv "${log_backups[@]}" "${backups}"
fi
sudo /etc/init.d/zipgateway start

# The zipgateway takes a long time to be fully operational
sleep 60

launch_reference_client

homeid=$(grep -m1 HomeID /var/log/zipgateway.log 2>/dev/null | cut -f4 -d' ' || true)
if [ -z "${homeid}" ]; then
  echo "Error: HomeID not found in /var/log/zipgateway.log." >&2
  echo "       Is zipgateway running? Did the log get rotated?" >&2
  exit 1
fi
CONTROLLER="Static Controller [${homeid}-0001-000]"

# Configure end devices from bed.tsv. For every end-device slot:
#   1. PIR: queue WAKE_UP_INTERVAL_SET so the device pulls it on next wake.
#   2. If the row carries a route, send PRIORITY_ROUTE_SET to the controller
#      (then wait so the controller commits before the next frame).
#   3. PIR: reset_board so the device wakes and the gateway can deliver any
#      queued frames before the burst loop starts.
for slot in $(bed_iter_end_devices); do
  end_node=$(bed_node_uri "${slot}" "${homeid}")

  if [ "${BED_ROLE[slot]}" = "pir" ]; then
    echo "send \"${end_node}\" COMMAND_CLASS_WAKE_UP WAKE_UP_INTERVAL_SET ${NL_WAKE_UP_INTERVAL_VALUE_SEC}01" >&3
  fi

  if [ -n "${BED_ROUTE[slot]}" ]; then
    echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${BED_ROUTE[slot]}" >&3
    sleep 0.2
  fi

  if [ "${BED_ROLE[slot]}" = "pir" ]; then
    reset_board "${BED_HOST[slot]}" \
      || echo "Warning: reset_board failed for ${BED_HOST[slot]}" >&2
  fi
done

# Give PIRs time to wake, drain queued frames, and settle before the burst.
sleep 30

END_TIME=$(( $(date +%s) + $(duration_to_seconds "${TEST_DURATION}") ))
echo "Endurance test will run until $(date -d "@${END_TIME}") (TEST_DURATION=${TEST_DURATION})"

while [ "$(date +%s)" -lt "${END_TIME}" ]
do
  for ((i=0; i<BURST_SIZE; i++))
  do

    # WARNING: Supervision_Get session id sits in bits 0-5, and thus it wraps
    # at 64. A receiving node ignores commands with the same Session ID.
    # If BURST_SIZE is ever raised past 64 and a previous session is still
    # pending on the receiver when its id is reused, the new command is
    # silently not reachable.
    SESSION="$(printf '%02X' $((i & 0x3F)))"

    # Endurance: drive every end-device slot every burst (PIRs included) to
    # maximise NCP tx-queue pressure. PIRs are sleepers, so the frame is
    # queued and delivered on their next wake; that is the point under load.
    for slot in $(bed_iter_end_devices); do
      case "${BED_ROLE[slot]}" in
        switch)    CMD="${SUPERVISION} ${SESSION}${SWITCH_BINARY_SET_ON}" ;;
        door_lock) CMD="${SUPERVISION} ${SESSION}${DOOR_LOCK_CONFIGURATION_GET}" ;;
        *)         continue ;;
      esac
      end_node=$(bed_node_uri "${slot}" "${homeid}")
      echo "send \"${end_node}\" ${CMD}" >&3
      sleep "${SEND_SLEEP:-0.15}"
    done
  done

  echo ""
  echo "$(date) CTRL+C to quit"
  echo ""
  sleep ${BURST_SLEEP}
done

echo "TEST_DURATION elapsed; shutting down."
clean_exit
