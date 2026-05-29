#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")/../../bench" && pwd)"
exec "${BENCH_DIR}/fetch_artifacts.sh"
