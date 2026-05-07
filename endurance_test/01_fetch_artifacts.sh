#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail

script_folder=$(dirname "$0")

if [ ! -f "${script_folder}/conf" ]; then
  echo "Error: conf file not found in ${script_folder}" >&2
  exit 1
fi

source "${script_folder}/conf"

if [ -z "${artifacts:-}" ]; then
  echo "Error: artifacts variable is not set in conf." >&2
  exit 1
fi

target_dir="${script_folder}/${artifacts}"
mkdir -p "${target_dir}"

if [ -z "${artifacts_url:-}" ] || [ "${artifacts_url}" = "not used in this test" ]; then
  cat <<EOF
Artifacts download is disabled for this test bed configuration.
Place the required firmware files manually under:
  ${target_dir}
EOF
  echo "Reminder: place zipgateway-7.18.03-Linux-armhf.deb under ./artifacts/."
  exit 0
fi

if ! command -v wget >/dev/null 2>&1; then
  echo "Error: wget is not installed." >&2
  exit 1
fi

wget -nc -P "${target_dir}" "${artifacts_url}/build.xml"
wget -nc -P "${target_dir}" "${artifacts_url}/conan.lock"

for firmware in "${HEX_1[@]}" "${HEX_2[@]}"; do
  filename=$(basename "${firmware}")
  wget -nc -P "${target_dir}" "${artifacts_url}/demo-applications.zip!/zwave_sample_app/brd4205b/${filename}"
done

echo "Artifacts ready in ${target_dir}."
echo "Reminder: place zipgateway-7.18.03-Linux-armhf.deb under ./artifacts/."
