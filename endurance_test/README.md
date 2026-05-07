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
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh` (rsyncs `zipgateway-*.deb` + `zgw_cleanup.sh` to `[zgw-host]`, runs cleanup + reinstall over SSH, reboots, waits up to `ZGW_REBOOT_WAIT_SEC` for SSH to come back) |
| 4 | `[test-controller]` -> `[zgw-host]` | copy the repo to `[zgw-host]`, then run `./04_provisioning.sh` there |
| 5 | manual              | power on devices one-by-one in node-id order; `commander device reset --ip <addr>` if needed |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` (`pl_list`, `list`)                         |
| 7 | `[zgw-host]`        | `./07_run.sh`                                                                     |
| 8 | manual              | monitor logs; CTRL+C to stop                                                      |

## Files

- `conf` -- machine + test parameters (sourced by every script).
- `utils.sh` -- shared functions (sourced).
- `01_..07_*.sh` -- step scripts above.
- `zgw_cleanup.sh` -- runs on `[zgw-host]`; invoked by `03_setup_zipgateway.sh` after rsync. Not user-triggered; missing numeric prefix is the signal.
- `power_off_all_boards.sh` -- manual recovery utility.

Step 3 prerequisites on `[zgw-host]`: SSH key-based access for `${ZGW_USER}` and passwordless `sudo`. Without those, `03_setup_zipgateway.sh` exits with a precondition error.

Run output (logs, captures, intermediate `dsks`) is gitignored.
