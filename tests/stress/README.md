<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Stress test

Burst load against the Z/IP Gateway with verdict checks running
in parallel. Currently scoped to **ST-01 (NCP tx-queue lockup)** and
**ST-02 (node false-dead events)**; additional stress tests will reuse
this directory layout via more files under `checks/`.

See `../../AGENTS.md` for hardware bed, host roles, and conventions.

Run all step scripts from this directory:

```bash
cd tests/stress
```

Shared bring-up lives in `../../bench/` (utils, fetch, flash, ZGW
setup, provisioning). This test owns its `conf` and `bed.tsv`

Important note: create `conf` and `bed.tsv` files, i.e., `cp conf.template
./conf && cp bed.tsv.template bed.tsv`

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 0 | `[test-controller]` | `./00_init_test_run.sh` mints `run_<UTC>/` |
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh <run_dir>` |
| 2 | `[test-controller]` | `./02_prepare_boards.sh <run_dir>` |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh <run_dir>` |
| 4 | `[test-controller]` | `./04_provisioning.sh <run_dir>` (pulls logs into `<run_dir>/04_provisioning/`) |
| 5 | manual              | power on devices one-by-one in node-id order |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` |
| 7 | `[test-controller]` | `./07_run.sh <run_dir>` (actually run the test, the probes and the analysis) |
| 8 | manual              | inspect the per-test verdicts `<run_dir>/*_verdict.txt` + `<run_dir>/*_summary.json` ) and pulled logs |

## Files in this directory

| File | Role |
|------|------|
| `00_init_test_run.sh` | mints `run_<UTC>/` (thin wrapper around `bench/init_test_run.sh`) |
| `01_..04_*.sh` | Step drivers; each takes `<run_dir>` as `$1` and tees into `<run_dir>/<step>/console.log` |
| `07_run.sh` | orchestrator + analysis |
| `run_on_host.sh` | stress burst loop on `[zgw-host]`; reads `RUN_DIR` from env, drives every end-device slot (>=16) each burst |
| `conf` | Z/IP Gateway + stress-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test |
| `checks/` | One script per verdict signal (heartbeat probes, log analyzers). See `checks/README.md`. |

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.
