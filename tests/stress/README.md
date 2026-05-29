<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Stress test

Burst load against the Z/IP Gateway with verdict checks running
in parallel. Currently scoped to **ST-01 (NCP tx-queue lockup)**;
additional stress tests will reuse this directory layout via more
files under `checks/`.

See `../../AGENTS.md` for hardware bed, host roles, and conventions.

Run all step scripts from this directory:

```bash
cd tests/stress
```

Shared bring-up lives in `../../bench/` (utils, fetch, flash, ZGW
setup, provisioning). This test owns its `conf` and `bed.tsv`



| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 0 | `[test-controller]` | `./00_init_test_run.sh` mints `run_<UTC>/` |
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh <run_dir>` |
| 2 | `[test-controller]` | `./02_prepare_boards.sh <run_dir>` |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh <run_dir>` |
| 4 | `[test-controller]` | `./04_provisioning.sh <run_dir>` (pulls logs into `<run_dir>/04_provisioning/`) |
| 5 | manual              | power on devices one-by-one in node-id order |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` |
| 7 | `[test-controller]` | `./07_run.sh <run_dir>` (detects HomeID once from the ZGW log, runs the load, stops the probe, pulls logs, runs the analyzer; writes `<run_dir>/verdict.txt` + `summary.json` and exits 0=PASS/1=FAIL/2=INCONCLUSIVE) |
| 8 | manual              | inspect `<run_dir>/verdict.txt`, `summary.json`, and pulled logs under `<run_dir>/07_run/` |

## Files in this directory

| File | Role |
|------|------|
| `00_init_test_run.sh` | mints `run_<UTC>/` (thin wrapper around `bench/init_test_run.sh`) |
| `01_..04_*.sh` | Step drivers; each takes `<run_dir>` as `$1` and tees into `<run_dir>/<step>/console.log` |
| `07_run.sh` | orchestrator: heartbeat probe + load driver + analyzer; exits with the ST-01 verdict code |
| `run_on_host.sh` | stress burst loop on `[zgw-host]`; reads `RUN_DIR` from env, drives every end-device slot (>=16) each burst |
| `conf` | Z/IP Gateway + stress-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test |
| `checks/` | One script per verdict signal (heartbeat probes, log analyzers). See `checks/README.md`. |

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.
