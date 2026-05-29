<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Endurance test

Long-duration burst load against the Z/IP Gateway. See `../../AGENTS.md`
for hardware bed, host roles, and conventions.

Run all step scripts from this directory:

```bash
cd tests/endurance
```

Shared bring-up lives in `../../bench/` (utils, fetch, flash, ZGW
setup, provisioning). This test owns its `conf` and `bed.tsv` and
its numbered scripts compose the bench helpers in order.

## 9-step flow

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh` (wget each URL from `bed.tsv` into `../../artifacts/`) |
| 2 | `[test-controller]` | `./02_prepare_boards.sh` (flashes boards, writes `../../artifacts/dsks`, powers off) |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh` (rsyncs `zipgateway-*.deb` + `zgw_cleanup.sh` to `[zgw-host]`, runs cleanup + reinstall over SSH, reboots, waits up to `ZGW_REBOOT_WAIT_SEC` for SSH to come back) |
| 4 | `[test-controller]` | `./04_provisioning.sh` (creates `run_<UTC>/`, stages workers + dsks on `[zgw-host]`, pulls logs including `provisioning_pl_add.log`, `reference_client.log`, and ZGW logs into that folder) |
| 5 | manual              | power on devices one-by-one in node-id order, waiting for the inclusion to complete |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` (`pl_list`, `list`)                         |
| 7 | `[test-controller]` | `./07_run.sh` (creates `run_<UTC>/`, runs burst loop on `[zgw-host]`, pulls logs into that folder). Stops on its own after `TEST_DURATION` (default `72h` in `conf`). |
| 8 | manual              | monitor logs; CTRL+C on `[test-controller]` propagates to the `[zgw-host]` for an early stop |

## Files in this directory

| File | Role |
|------|------|
| `01_..04_*.sh`, `07_run.sh` | Step drivers (01-04 exec `bench/`; 07 rsyncs bench + `run_on_host.sh`) |
| `run_on_host.sh` | burst loop on `[zgw-host]`; invoked by `07_run.sh` |
| `conf` | Z/IP Gateway + endurance-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test (JLink, board, role, route, firmware URLs) |

Shared helpers (`utils.sh`, host workers except `run_on_host.sh`) live in `../../bench/`. See `../../bench/README.md`.

Steps 3, 4, and 7 prerequisites on `[zgw-host]`: SSH key-based access for `${ZGW_USER}` and passwordless `sudo`. Without those, the driver scripts exit with a precondition error.

Run output lives under `run_<UTC>/` (logs, captures). Gitignored.

## Bed description

`bed.tsv` is one tab-separated row per slot. Lines starting with `#` and blank lines are ignored. Columns (in order):

| Column | Meaning |
|---|---|
| `id` | Zero-based row id; must match the file order. |
| `jlink_host` | JLink-IP DNS name (port 4902 control). |
| `board` | Commander `--board` family (e.g. `brd4205b`). |
| `device` | Commander `--device` token (e.g. `ZGM230S`). |
| `role` | `zniffer`, `controller`, `switch`, `door_lock`, or `pir`. |
| `route` | `PRIORITY_ROUTE_SET` hex string; `-` for zniffer/controller. |
| `region` | `MFG_ZWAVE_COUNTRY_FREQ` hex (e.g. `0x01` US, `0x09` US-LR); `-` to inherit `REGION` from `conf`. |
| `firmware` | Full Artifactory URL (`zip!/member` syntax supported by wget). |
| `bootloader` | Full Artifactory URL; `-` if no separate bootloader. |

To add a board: append a row with the next `id` number; `01_fetch_artifacts.sh` will wget any new URL and `02_prepare_boards.sh` will flash it on the next run.
