<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Artifacts

Input binaries used by the test bench. This directory is gitignored
except for this README and `.gitkeep`. Drop the files here; do not
commit them.

Inventory and sources are documented in detail in
[../endurance_test/README.md](../endurance_test/README.md). Short
version:

- Radio binaries (`*.s37`, `*.hex`, `build.xml`, `conan.lock`) are
  downloaded by `endurance_test/01_fetch_artifacts.sh` from the SDK
  artifactory build referenced in `endurance_test/conf`.
- The ZGW `.deb` (e.g. `zipgateway-7.18.03-Linux-armhf.deb`) is
  dropped manually after downloading it via Simplicity Studio or pulling it
  from a CI build.
