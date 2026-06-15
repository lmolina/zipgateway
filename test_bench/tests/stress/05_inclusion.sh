#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Step 05: automated SmartStart inclusion of the end devices, in slot order.
# Replaces the former manual steps 05/06. Runs on [test-controller]: it
# power-cycles each board over JLink-IP and watches the ZGW log over SSH to
# confirm the right device (by NWI HomeID from its DSK) is included with the
# expected node id before moving to the next.
#
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <run_dir>" >&2
  echo "       run ./00_init_test_run.sh first." >&2
  exit 2
fi

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
export TEST_DIR
BENCH_DIR="$(cd "${TEST_DIR}/../../bench" && pwd)"

# shellcheck source=conf
source "${TEST_DIR}/conf"
# shellcheck source=../../bench/utils.sh
source "${BENCH_DIR}/utils.sh"

run_dir_attach "$1"
STEP_NAME="05_inclusion"
STEP_DIR="${RUN_DIR}/${STEP_NAME}"
mkdir -p "${STEP_DIR}"
export STEP_NAME STEP_DIR

"${BENCH_DIR}/inclusion.sh" 2>&1 | tee "${STEP_DIR}/console.log"
exit "${PIPESTATUS[0]}"
