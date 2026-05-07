#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

function power_on_board {
  local host="$1"
  local port=4902
  echo "Powering on board $host..."
  {
    sleep 1
    echo "target go"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
  if [ $? -eq 0 ]; then
    echo "Board $host powered on."
  else
    echo "Warning: Could not confirm power on for $host" >&2
  fi
}

function power_off_board {
  local host="$1"
  local port=4902
  echo "Powering off board $host..."
  {
    sleep 1
    echo "target halt"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
  if [ $? -eq 0 ]; then
    echo "Board $host halted."
  else
    echo "Warning: Could not confirm halted for $host" >&2
  fi
}

function reset_board {
  local host="$1"
  local port=4902
  echo "Resetting board $host..."
  {
    sleep 1
    echo "sys reset sys"
    sleep 1
  } | telnet "$host" $port 2>/dev/null | grep -q "OK"
}

function launch_reference_client {
  echo "Launching reference client"
  reference_client="$1"

  # HACK: to re-launch the reference_client when it fails due to sigfault...
  exec 3> >(
  while true;
  do
    "$reference_client" -g ${logs_dir}/reference_client.log -s ${ZipLanIp6} -p ${ZipPSK}
    sleep 1
  done
)
  sleep 1
}

function clean_exit {
  echo "Sutting down reference_client!"
  exec 3>&-
  wait

  mkdir -p "${logs_dir}"
  cp /var/log/zipgateway.log /var/log/ziprouter.serlog "${logs_dir}"
  echo "End Time: $(date)" >> "${logs_dir}/end_time"

  echo "Bye ..."

  kill 0
  exit 0
}

function activate_radio_tone {
  echo "$(date): Activating radio tone"
  echo "setTxTone 1" > "${RAIL_TEST_908}"
  echo "setTxTone 1" > "${RAIL_TEST_916}"
}

function deactivate_radio_tone {
  echo "$(date): Deactivating radio tone"
  echo "setTxTone 0" > "${RAIL_TEST_908}"
  echo "setTxTone 0" > "${RAIL_TEST_916}"
}

function setup_rail_test {
  # To be sure, stop the tone
  echo "reset" > "${RAIL_TEST_908}"
  echo "reset" > "${RAIL_TEST_916}"
  sleep 1

  echo "setDebugMode 1" > "${RAIL_TEST_908}"
  echo "setDebugMode 1" > "${RAIL_TEST_916}"
  sleep 0.1

  echo "rx 0" > "${RAIL_TEST_908}"
  echo "rx 0" > "${RAIL_TEST_916}"
  sleep 0.1

  echo "freqOverride 908400000" > "${RAIL_TEST_908}"
  echo "freqOverride 916000000" > "${RAIL_TEST_916}"
  sleep 0.1
}
