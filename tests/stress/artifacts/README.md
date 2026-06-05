<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Artifacts

Input binaries used by the test bench. This directory is gitignored
except for this README. Drop the files here; do not commit them.

- Radio binaries (`*.s37`, `*.hex`, `build.xml`, `conan.lock`) are
  downloaded by `tests/<name>/01_fetch_artifacts.sh` from the SDK
  Artifactory build referenced in that test's `bed.tsv`
  (e.g. `tests/stress/bed.tsv`).
- The ZGW `.deb` (e.g. `zipgateway-7.18.03-Linux-armhf.deb`) is
  dropped manually after downloading it via Simplicity Studio or pulling it
  from a CI build.

Intermediate output `dsks` is written here by `02_prepare_boards.sh` and
consumed by `04_provisioning.sh`.
