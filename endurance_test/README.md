<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Endurance test

Long-duration burst load against the Z/IP Gateway. See `../AGENTS.md`
for hardware bed, host roles, and conventions.

## 9-step flow

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh` (wget each URL from `bed.tsv` into `../artifacts/`) |
| 2 | `[test-controller]` | `./02_prepare_boards.sh` (flashes boards, writes `dsks`, powers off)              |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh` (rsyncs `zipgateway-*.deb` + `zgw_cleanup.sh` to `[zgw-host]`, runs cleanup + reinstall over SSH, reboots, waits up to `ZGW_REBOOT_WAIT_SEC` for SSH to come back) |
| 4 | `[test-controller]` | `./04_provisioning.sh` (rsyncs `provision_on_host.sh` + `utils.sh` + `conf` + `${artifacts}/dsks` to `[zgw-host]`, runs the worker over SSH, pulls `${logs_dir}/` back) |
| 5 | manual              | power on devices one-by-one in node-id order, waiting for the inclusion to complete |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` (`pl_list`, `list`)                         |
| 7 | `[test-controller]` | `./07_run.sh` (rsyncs `run_on_host.sh` + `utils.sh` + `conf` to `[zgw-host]`, runs test over SSH, pulls logs back). Stops on its own after `TEST_DURATION` (default `72h` in `conf`). |
| 8 | manual              | monitor logs; CTRL+C on `[test-controller]` propagates to the `[zgw-host]` for an early stop |

## Files

- `bed.tsv` -- per-slot bed description (jlink host, board, device, role, bootloader, firmware, route, region). One row per slot; edit this when you add or change a board. See "Bed description" below.
- `conf` -- machine + test parameters (sourced by every script).
- `utils.sh` -- shared functions, including the `bed_load` / `bed_iter_end_devices` helpers that parse `bed.tsv` into `BED_*` arrays.
- `01_..07_*.sh` -- step scripts above.
- `zgw_cleanup.sh` -- runs on `[zgw-host]`; invoked by `03_setup_zipgateway.sh` after rsync. Not user-triggered; missing numeric prefix is the signal.
- `provision_on_host.sh` -- runs on `[zgw-host]`; invoked by `04_provisioning.sh` after rsync. Same convention: no numeric prefix = host worker.
- `run_on_host.sh` -- runs on `[zgw-host]`; invoked by `07_run.sh` after rsync. Same convention.
- `power_off_all_boards.sh` -- manual recovery utility.

Steps 3, 4, and 7 prerequisites on `[zgw-host]`: SSH key-based access for `${ZGW_USER}` and passwordless `sudo`. Without those, the driver scripts exit with a precondition error.

Run output (logs, captures, intermediate `dsks`) is gitignored.

## Bed description

`bed.tsv` is one tab-separated row per slot. Lines starting with `#` and blank lines are ignored. Columns (in order):

| Column | Meaning |
|---|---|
| `slot` | Zero-based slot index; must match the file order. |
| `jlink_host` | JLink-IP DNS name (port 4902 control). |
| `board` | Commander `--board` family (e.g. `brd4205b`). |
| `device` | Commander `--device` token (e.g. `ZGM230S`). |
| `role` | `zniffer`, `controller`, `switch`, `door_lock`, or `pir`. |
| `bootloader` | Full Artifactory URL; `-` if no separate bootloader. |
| `firmware` | Full Artifactory URL (`zip!/member` syntax supported by wget). |
| `route` | `PRIORITY_ROUTE_SET` hex string; `-` for zniffer/controller. |
| `region` | `MFG_ZWAVE_COUNTRY_FREQ` hex (e.g. `0x01` US, `0x00` EU, `0x09` US-LR); `-` to inherit `REGION` from `conf`. Flashed at step 2. |

To add a board: append a row with the next `slot` number; `01_fetch_artifacts.sh` will wget any new URL and `02_prepare_boards.sh` will flash it on the next run.
