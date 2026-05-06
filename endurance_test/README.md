<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Endurance test

Long-duration burst load against the Z/IP Gateway. See `../AGENTS.md`
for hardware bed, host roles, and conventions.

## 9-step flow

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh` (no-op when `artifacts_url` is unused; place files in `../artifacts/`) |
| 2 | `[test-controller]` | `./02_prepare_boards.sh` (flashes boards, writes `dsks`, powers off)              |
| 3 | `[zgw-host]`        | `./03_zipgw_cleanup.sh` (reinstalls ZGW from the `.deb` in `../artifacts/`)       |
| 4 | manual              | `sudo reboot` the `[zgw-host]`                                                    |
| 5 | `[test-controller]` -> `[zgw-host]` | copy `dsks` to `[zgw-host]`, then run `./05_provisioning.sh` there |
| 6 | manual              | power on devices one-by-one in node-id order; `commander device reset --ip <addr>` if needed |
| 7 | `[zgw-host]`        | verify node IDs in `reference_client` (`pl_list`, `list`)                         |
| 8 | `[zgw-host]`        | `./08_run.sh`                                                                     |
| 9 | manual              | monitor logs; CTRL+C to stop                                                      |

## Files

- `conf` -- machine + test parameters (sourced by every script).
- `utils.sh` -- shared functions (sourced).
- `01_..08_*.sh` -- step scripts above.
- `power_off_all_boards.sh` -- manual recovery utility.

Run output (logs, captures, intermediate `dsks`) is gitignored.
