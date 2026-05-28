#!/usr/bin/env bash
# SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/>
#
# SPDX-License-Identifier: LicenseRef-MSLA

set -euo pipefail
set +H

script_folder=$(dirname "$0")

if [ ! -f "${script_folder}/conf" ]; then
  echo "Error: conf file not found in ${script_folder}" >&2
  exit 1
fi
if [ ! -f "${script_folder}/utils.sh" ]; then
  echo "Error: utils.sh not found in ${script_folder}" >&2
  exit 1
fi

source "${script_folder}/conf"
source "${script_folder}/utils.sh"

if [ -z "${ARTIFACTS_DIR:-}" ]; then
  echo "Error: ARTIFACTS_DIR variable is not set in conf." >&2
  exit 1
fi
if [ -z "${BED_TSV:-}" ]; then
  echo "Error: BED_TSV variable is not set in conf." >&2
  exit 1
fi

target_dir="${ARTIFACTS_DIR}"
mkdir -p "${target_dir}"

if ! command -v wget >/dev/null 2>&1; then
  echo "Error: wget is not installed." >&2
  exit 1
fi

bed_load "${BED_TSV}"

url_count=0
while IFS= read -r url; do
  [ -z "${url}" ] && continue
  url_count=$((url_count + 1))
  relpath=$(bed_artifact_relpath_from_url "${url}")
  dest="${target_dir}/${relpath}"
  mkdir -p "$(dirname "${dest}")"
  echo "Fetching ${relpath}"
  wget -nc -O "${dest}" -- "${url}"
done < <(bed_unique_artifact_urls)

if [ "${url_count}" -eq 0 ]; then
  cat <<EOF
No Artifactory URLs found in ${BED_TSV}.
Place firmware files manually under mirrored paths in:
  ${target_dir}
EOF
fi

echo "Artifacts ready in ${target_dir}."
echo "Reminder: place zipgateway-7.18.03-Linux-armhf.deb under ${ARTIFACTS_DIR}/."
