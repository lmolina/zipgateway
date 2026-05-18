<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Stress test

Burst load against the Z/IP Gateway with verdict checks running
in parallel.

ST-03 and ST-05 intentionally share the same ZGW probe. The probe
records per-sample latency and status once. ST-03 consumes the
liveness signal while ST-05 consumes the latency signal.

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
| 4 | `[test-controller]` | `./04_provisioning.sh <run_dir>` loads the SmartStart provisioning list |
| 5 | `[test-controller]` | `./05_inclusion.sh <run_dir>` power-cycles each end device in slot order |
| 7 | `[test-controller]` | `./07_run.sh <run_dir>` (actually run the test, the probes and the analysis) |
| 8 | manual              | inspect the per-test verdicts `<run_dir>/*_verdict.txt` + `<run_dir>/*_summary.json` and pulled logs |

## Files in this directory

| File | Role |
|------|------|
| `00_init_test_run.sh` | mints `run_<UTC>/` (thin wrapper around `bench/init_test_run.sh`) |
| `01_..05_*.sh` | Step drivers; each takes `<run_dir>` as `$1` and tees into `<run_dir>/<step>/console.log` |
| `07_run.sh` | orchestrator + analysis |
| `run_on_host.sh` | stress burst loop on `[zgw-host]` |
| `conf` | Z/IP Gateway + stress-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test |
| `checks/` | One script per verdict signal (heartbeat probes, log analyzers). See `checks/README.md`. |

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.
