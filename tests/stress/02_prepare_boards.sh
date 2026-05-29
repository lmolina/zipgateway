#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

export TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH_DIR="$(cd "${TEST_DIR}/../../bench" && pwd)"
exec "${BENCH_DIR}/prepare_boards.sh"
