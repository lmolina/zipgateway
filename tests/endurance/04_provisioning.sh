#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <run_dir>" >&2
  echo "       run ./00_init_test_run.sh first." >&2
  exit 2
fi

export TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "${TEST_DIR}/../../bench" && pwd)"

# shellcheck source=conf
source "${TEST_DIR}/conf"
# shellcheck source=../../bench/utils.sh
source "${BENCH_DIR}/utils.sh"

run_dir_attach "$1"
STEP_NAME="04_provisioning"
STEP_DIR="${RUN_DIR}/${STEP_NAME}"
STEP_REMOTE_DIR="${RUN_REMOTE_DIR}/${STEP_NAME}"
mkdir -p "${STEP_DIR}"
export STEP_NAME STEP_DIR STEP_REMOTE_DIR

"${BENCH_DIR}/provisioning.sh" 2>&1 | tee "${STEP_DIR}/console.log" || true
exit "${PIPESTATUS[0]}"
