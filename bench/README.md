<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Bench (shared library)

Shared bring-up logic for all tests in this repository. Each test under
`tests/<name>/` owns its own numbered `0N_*.sh` scripts that call into
this directory.

## Contents

| File | Role |
|------|------|
| `conf` | Z/IP Gateway + test parameters (`bench/conf`; sourced by every script) |
| `bed.tsv` | Per-device description (JLink, board, role, route, firmware URLs) |
| `utils.sh` | `bed_load`, board power helpers, artifact path helpers |
| `fetch_artifacts.sh` | wget unique URLs from `bed.tsv` into repo-root `artifacts/` |
| `prepare_boards.sh` | flash boards, write `artifacts/dsks`, power off |
| `setup_zipgateway.sh` | rsync ZGW `.deb` to `[zgw-host]`, cleanup, reinstall, reboot |
| `provisioning.sh` | SSH driver: stage workers + dsks, run SmartStart, pull logs into `run_<UTC>/` |
| `provision_on_host.sh` | SmartStart worker on `[zgw-host]`; invoked by `provisioning.sh` |
| `zgw_cleanup.sh` | purge/reinstall ZGW on `[zgw-host]` |
| `power_off_all_boards.sh` | manual recovery: power off every slot in `bed.tsv` |

Run a test from its directory, e.g. `cd tests/endurance && ./01_fetch_artifacts.sh`.
