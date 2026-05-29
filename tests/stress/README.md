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
(forked from endurance for now; tune for ST-01 before T8).

## Flow

The first four steps are identical to the endurance test (same
SmartStart bring-up):

| # | Where               | Action                                                                            |
|---|---------------------|-----------------------------------------------------------------------------------|
| 1 | `[test-controller]` | `./01_fetch_artifacts.sh` |
| 2 | `[test-controller]` | `./02_prepare_boards.sh` |
| 3 | `[test-controller]` | `./03_setup_zipgateway.sh` |
| 4 | `[test-controller]` | `./04_provisioning.sh` (creates `run_<UTC>/`, pulls logs into that folder) |
| 5 | manual              | power on devices one-by-one in node-id order |
| 6 | `[zgw-host]`        | verify node IDs in `reference_client` |
| 7 | `[test-controller]` | `./07_run.sh` (load now; parallel checks + `run_<UTC>/verdict.txt` wired in by a later task) |
| 8 | manual              | inspect `run_<UTC>/verdict.txt`, `summary.json`, and pulled logs |

## Files in this directory

| File | Role |
|------|------|
| `01_..04_*.sh` | Step drivers (01-03 exec `bench/`; 04 wraps `bench/provisioning.sh` after creating `run_<UTC>/`) |
| `07_run.sh` | load driver (stages + runs `run_on_host.sh`, pulls logs); checks + analyzer wiring lands later |
| `run_on_host.sh` | stress burst loop on `[zgw-host]`; drives every end-device slot (>=16) each burst |
| `conf` | Z/IP Gateway + stress-test parameters (sourced by all scripts; sets `BED_TSV` to the file next to it) |
| `bed.tsv` | Per-device description for this test |
| `checks/` | One script per verdict signal (heartbeat probes, log analyzers). See `checks/README.md`. |

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.

## Bed description

`bed.tsv` is initially a copy of `tests/endurance/bed.tsv`; tune for
ST-01 as needed. ST-01 requires >=16 end devices; testbed-1
currently lists 19 end-device slots. Use `REGION=0x01` (US classic,
no LR) until ZGW-3426 is resolved.
