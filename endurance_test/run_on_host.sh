#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

mydir=$(dirname "$0")
source "${mydir}/conf"
source "${mydir}/utils.sh"

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
END_NODE_7="dut-8.${LOCATION} [${homeid}-0012-000]"
END_NODE_8="dut-9.${LOCATION} [${homeid}-0013-000]"

# Configure NL devices: interval and primary route
echo "send \"${END_NODE_7}\" COMMAND_CLASS_WAKE_UP WAKE_UP_INTERVAL_SET ${NL_WAKE_UP_INTERVAL_VALUE_SEC}01" >&3
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_7}" >&3
reset_board "${ADDR[8]}"
sleep 10

echo "send \"${END_NODE_8}\" COMMAND_CLASS_WAKE_UP WAKE_UP_INTERVAL_SET ${NL_WAKE_UP_INTERVAL_VALUE_SEC}01" >&3
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_8}" >&3
reset_board "${ADDR[9]}"
sleep 10

# Set up route for other devices
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_1}" >&3
sleep 0.2
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_2}" >&3
sleep 0.2
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_3}" >&3
sleep 0.2
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_4}" >&3
sleep 0.2
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_5}" >&3
sleep 0.2
echo "send \"${CONTROLLER}\" COMMAND_CLASS_NETWORK_MANAGEMENT_INSTALLATION_MAINTENANCE PRIORITY_ROUTE_SET ${ROUTE_END_NODE_6}" >&3
sleep 0.2

while true
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

    CMD="${SUPERVISION} ${SESSION}${DOOR_LOCK_CONFIGURATION_GET}"
    echo "send \"${END_NODE_5}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_6}\" ${CMD}" >&3
    sleep 0.15

    CMD="COMMAND_CLASS_SECURITY_2 SECURITY_2_NONCE_GET"
    echo "send \"${END_NODE_1}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_2}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_3}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_4}\" ${CMD}" >&3
    sleep 0.15

    echo "send \"${END_NODE_5}\" ${CMD}" >&3
    sleep 0.15
    echo "send \"${END_NODE_6}\" ${CMD}" >&3
    sleep 0.15
  done

  echo ""
  echo "$(date) CTRL+C to quit"
  echo ""
  sleep ${BURST_SLEEP}
done
