<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Stress test checks

One script per stress-test verdict signal. Each check is independent
and re-runnable against an existing `run_<UTC>/` folder.

Conventions:

- Heartbeat / probe scripts run **alongside** the stress load. They
  emit timestamped CSV lines into the step subfolder
  (`<run_dir>/07_run/`) so the analyzer (post-run) can compute
  pass/fail.
- Analyzer scripts run **after** the stress load stops. They scan
  `<run_dir>/` (CSV under `07_run/`, ZGW log under `07_run/`) and
  write `verdict.txt` + `summary.json` at the run root. Exit code
  reflects the verdict (0 = pass, non-zero = fail per the test's DoD).

Checks:

| File | Test | Signal | Status |
|------|------|--------|--------|
| `st01_heartbeat.sh` | ST-01 | mDNS (`avahi-resolve`) liveness probe of ZGW from `[test-controller]`; one timestamped CSV row per sample, `status` in {ok,fail,timeout} | done |
| `st01_analyze.sh`   | ST-01 | post-run: heartbeat-timeout streak (reliable) + ZGW-log tx-marker gap (corroborating) -> `verdict.txt` + `summary.json` | done |

`st01_heartbeat.sh` is standalone-runnable (`--out FILE --homeid HEX
[--cadence-s S] [--timeout-s S] [--duration-s S]`).

`st01_analyze.sh` is standalone-runnable (`--run-dir DIR [--conf FILE]`).
It locates the heartbeat CSV and `zipgateway.log` under the run folder,
applies a strict verdict (both signals must agree for PASS), and exits
0=PASS / 1=FAIL / 2=INCONCLUSIVE. Thresholds and the (version-coupled)
tx-marker regex are configurable in `tests/stress/conf`
(`ST01_MAX_TIMEOUT_STREAK`, `ST01_MAX_TX_GAP_S`, `ST01_TX_MARKER_RE`);
verify the regex against a real ZGW log at the shakedown.

`tests/stress/07_run.sh` starts the heartbeat in the background
before the load loop and calls the analyzer once the load stops.
