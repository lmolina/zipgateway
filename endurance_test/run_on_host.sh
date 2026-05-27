#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

mydir=$(dirname "$0")
source "${mydir}/conf"
source "${mydir}/utils.sh"

bed_load "${BED_TSV}"

START_TIME=$(date +%s)

mkdir -p "${logs_dir}"
trap clean_exit SIGINT
trap launch_reference_client SIGCHLD

sudo /etc/init.d/zipgateway stop
backups="/var/log/zipgateway-$(date +%Y%m%dT%H%M%S).old"
sudo mkdir -p "${backups}"
sudo mv /var/log/ziprouter.serlog* /var/log/zipgateway.log* "${backups}"
sudo /etc/init.d/zipgateway start

# The zipgateway takes a long time to be fully operational
sleep 60

launch_reference_client

homeid=$(grep HomeID /var/log/zipgateway.log | cut -f4 -d' ')
CONTROLLER="Static Controller [${homeid}-0001-000]"

END_NODE_1="dut-2.${LOCATION} [${homeid}-0006-000]"
END_NODE_2="dut-3.${LOCATION} [${homeid}-0007-000]"
END_NODE_3="dut-4.${LOCATION} [${homeid}-0008-000]"
END_NODE_4="dut-5.${LOCATION} [${homeid}-0009-000]"
END_NODE_5="dut-6.${LOCATION} [${homeid}-0010-000]"
END_NODE_6="dut-7.${LOCATION} [${homeid}-0011-000]"
END_NODE_9="dut-10.${LOCATION} [${homeid}-0014-000]"
END_NODE_10="dut-11.${LOCATION} [${homeid}-0015-000]"
END_NODE_11="dut-12.${LOCATION} [${homeid}-0016-000]"
END_NODE_12="dut-13.${LOCATION} [${homeid}-0017-000]"
END_NODE_13="dut-14.${LOCATION} [${homeid}-0018-000]"

# Configure end devices from bed.tsv. For every end-device slot:
#   1. PIR: queue WAKE_UP_INTERVAL_SET so the device pulls it on next wake.
#   2. If the row carries a route, send PRIORITY_ROUTE_SET to the controller
#      (then wait 0.2s so the controller commits before the next frame).
#   3. PIR: reset_board so the device wakes and the gateway can deliver any
#      queued frames before the burst loop starts.
for slot in $(bed_iter_end_devices); do
  end_node="dut-${slot}.${LOCATION} [${homeid}-$(printf '%04d' $((slot + 4)))-000]"

  if [ "${BED_ROLE[slot]}" = "pir" ]; then
    echo "send \"${end_node}\" COMMAND_CLASS_WAKE_UP WAKE_UP_INTERVAL_SET ${NL_WAKE_UP_INTERVAL_VALUE_SEC}01" >&3
  fi

  if [ -n "${BED_ROUTE[slot]}" ]; then
    echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${BED_ROUTE[slot]}" >&3
    sleep 0.2
  fi

  if [ "${BED_ROLE[slot]}" = "pir" ]; then
    reset_board "${BED_HOST[slot]}"
  fi
done

# Give PIRs time to wake, drain queued frames, and settle before the burst.
sleep 30

END_TIME=$(date -d "now + ${TEST_DURATION}" +%s)
echo "Test will run until $(date -d "@${END_TIME}") (TEST_DURATION=${TEST_DURATION})"

while [ "$(date +%s)" -lt "${END_TIME}" ]
do
  for ((i=0; i<BURST_SIZE; i++))
  do

    # HACK: quick and dirty ;-)
    # CC suppervision uses a 5-bit session id. A hack to fake the session ID. Since the loop goes
    # until 10, it should be OK to do this, although there may be problems if the limit of the loop
    # is increased.
    SESSION="$(printf "%02d" ${i})"

    CMD="${SUPERVISION} ${SESSION}${SWITCH_BINARY_SET_ON}"
    echo "send \"${END_NODE_1}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_2}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_3}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_4}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_9}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_10}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_11}\" ${CMD}" >&3
    sleep 0.15

    CMD="${SUPERVISION} ${SESSION}${DOOR_LOCK_CONFIGURATION_GET}"
    echo "send \"${END_NODE_5}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_6}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_12}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_13}\" ${CMD}" >&3
    sleep 0.15
  done

  echo ""
  echo "$(date) CTRL+C to quit"
  echo ""
  sleep ${BURST_SLEEP}
done

echo "TEST_DURATION elapsed; shutting down."
clean_exit
