#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA
#
# Step 00: create the run folder for one full test cycle.
#
# Every numbered step (01..07) takes the same <run_dir> as a positional
# argument, so this script is the single point that stamps it. It
# `mkdir`s the run folder (fails if it already exists, no -p surprise)
# and drops a manifest.txt with provenance.
#
# Usage:
#   00_init_test_run.sh [<run_dir>]
#
# <run_dir> defaults to ${TEST_DIR}/run_<UTC>. Relative paths are
# resolved against the current working directory.
#
# Required env (set by the tests/<name>/00_init_test_run.sh wrapper):
#   TEST_DIR  the test directory (where conf + bed.tsv live).

set -euo pipefail

if [ -z "${TEST_DIR:-}" ]; then
  echo "Error: TEST_DIR is not set." >&2
  echo "       call this script from a tests/<name>/ wrapper." >&2
  exit 1
fi
if [ ! -f "${TEST_DIR}/conf" ]; then
  echo "Error: conf file not found in ${TEST_DIR}" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${TEST_DIR}/conf"

run_dir="${1:-${TEST_DIR}/run_$(date -u +%Y%m%dT%H%M%SZ)}"

parent_dir="$(dirname "${run_dir}")"
if [ ! -d "${parent_dir}" ]; then
  echo "Error: parent directory does not exist: ${parent_dir}" >&2
  exit 1
fi
run_dir="$(cd "${parent_dir}" && pwd)/$(basename "${run_dir}")"

if [ -e "${run_dir}" ]; then
  echo "Error: run dir already exists: ${run_dir}" >&2
  echo "       refusing to overwrite. Pick a new path." >&2
  exit 1
fi

# No -p: keeps the contract simple (parent must exist; target must not).
mkdir "${run_dir}"

manifest="${run_dir}/manifest.txt"
{
  echo "test_dir:      ${TEST_DIR}"
  echo "run_dir:       ${run_dir}"
  echo "created:       $(date -u +%FT%TZ)"
  echo "host:          $(hostname)"
  echo "user:          ${USER:-$(id -un)}"
  echo "region:        ${REGION:-<unset>}"
  echo "zgw_host:      ${ZGW_HOST:-<unset>}"
  echo "zgw_user:      ${ZGW_USER:-<unset>}"
  echo "zgw_stage_dir: ${ZGW_STAGE_DIR:-<unset>}"
} > "${manifest}"

echo "Run folder created: ${run_dir}"
echo "Pass this path as the first argument to 01..04 and 07."
