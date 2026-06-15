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
STEP_DIR="${RUN_DIR}/01_fetch_artifacts"
mkdir -p "${STEP_DIR}"
export STEP_DIR

"${BENCH_DIR}/fetch_artifacts.sh" 2>&1 | tee "${STEP_DIR}/console.log" || true
exit "${PIPESTATUS[0]}"
