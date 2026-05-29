#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

export TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "${TEST_DIR}/../../bench" && pwd)"

# shellcheck source=conf
source "${TEST_DIR}/conf"
# shellcheck source=../../bench/utils.sh
source "${BENCH_DIR}/utils.sh"

run_dir_init "${TEST_DIR}"
export LOG_PULL_DIR="${RUN_DIR}"

exec "${BENCH_DIR}/provisioning.sh"
