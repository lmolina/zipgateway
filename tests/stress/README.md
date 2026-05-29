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

Shared bring-up lives in `../../bench/` (conf, bed.tsv, utils, fetch,
flash, ZGW setup). This test's numbered scripts define the order.

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
| 7 | `[test-controller]` | `./07_run.sh` (load + parallel checks; writes `run_<UTC>/verdict.txt`) -- **T4..T7** |
| 8 | manual              | inspect `run_<UTC>/verdict.txt`, `summary.json`, and pulled logs |

## Files in this directory

| File | Role |
|------|------|
| `01_..04_*.sh` | Step drivers (01-03 exec `bench/`; 04 wraps `bench/provisioning.sh` after creating `run_<UTC>/`) |
| `07_run.sh` | (T4..T7) load driver + parallel checks + analyzer wiring |
| `run_on_host.sh` | (T4) burst loop on `[zgw-host]`; >=16 devices |
| `checks/` | One script per verdict signal (heartbeat probes, log analyzers). See `checks/README.md`. |

Run output lives under `run_<UTC>/` (logs, captures, verdict). Gitignored.

## Bed description

Same `../../bench/bed.tsv` as the endurance test. ST-01 requires
>=16 end devices; testbed-1 currently lists 19 end-device slots.
Use `REGION=0x01` (US classic, no LR) until ZGW-3426 is resolved.
