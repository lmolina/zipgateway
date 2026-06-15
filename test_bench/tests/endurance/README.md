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

Important note: create `conf` and `bed.tsv` files, i.e., `cp conf.template
./conf && cp bed.tsv.template bed.tsv`

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 0 | `[test-controller]` | `./00_init_test_run.sh <run_dir>` mints `run_dir/` and prints its path |
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh <run_dir>` (wget each URL from `bed.tsv` into `./artifacts/`) |
| 2 | `[test-controller]` | `./02_prepare_boards.sh <run_dir>` (flashes boards, writes `./artifacts/dsks`, powers off) |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh <run_dir>` (rsyncs `zipgateway-*.deb` + `zgw_cleanup.sh` to `[zgw-host]`, runs cleanup + reinstall over SSH, reboots, waits up to `ZGW_REBOOT_WAIT_SEC` for SSH to come back) |
| 4 | `[test-controller]` | `./04_provisioning.sh <run_dir>` loads the SmartStart provisioning list |
| 5 | `[test-controller]` | `./05_inclusion.sh <run_dir>` power-cycles each end device in slot order |
| 7 | `[test-controller]` | `./07_run.sh <run_dir>` (runs ET-01: burst loop on `[zgw-host]`, local heartbeat probe, pulled logs). |

## Files in this directory

| File | Role |
|------|------|
| `00_init_test_run.sh` | mints `run_<UTC>/` (thin wrapper around `bench/init_test_run.sh`) |
| `01_..05_*.sh`, `07_run.sh` | Step drivers; each takes `<run_dir>` as `$1` and tees into `<run_dir>/<step>/console.log` |
| `run_on_host.sh` | ET-01 burst loop on `[zgw-host]`; invoked by `07_run.sh` (reads `RUN_DIR` from env) |
| `checks/` | ET-01 verdict logic; currently the endurance-local ST-01 heartbeat probe and analyzer |
| `conf` | Z/IP Gateway + endurance-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test (JLink, board, role, route, firmware URLs) |

Shared helpers (`utils.sh`, host workers except `run_on_host.sh`) live in `../../bench/`. See `../../bench/README.md`.

Steps 3, 4, 5, and 7 prerequisites on `[zgw-host]`: SSH key-based access for `${ZGW_USER}` and passwordless `sudo`. Without those, the driver scripts exit with a precondition error.

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.
