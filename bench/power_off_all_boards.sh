#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -e
# set -x

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
if [ ! -f "${script_folder}/utils.sh" ]; then
  echo "Error: utils.sh not found in $script_folder" >&2
  exit 1
fi

source "${TEST_DIR}/conf"
source "${script_folder}/utils.sh"

for addr in "${ADDR[@]}";
do
  power_off_board "$addr"
  echo
done
