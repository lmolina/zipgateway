<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Stress test checks

One script per stress-test verdict signal. Each check is independent
and re-runnable against an existing `run_<UTC>/` folder.

Conventions:

- Heartbeat / probe scripts run **alongside** the stress load. They
  emit timestamped CSV lines into a file under `run_<UTC>/` so the
  analyzer (post-run) can compute pass/fail.
- Analyzer scripts run **after** the stress load stops. They consume
  the CSV + ZGW log files from `run_<UTC>/` and write `verdict.txt`
  + `summary.json` into the same folder. Exit code reflects the
  verdict (0 = pass, non-zero = fail per the test's DoD).

Planned checks (filenames are placeholders until T5/T6 land):

| File | Test | Signal |
|------|------|--------|
| `st01_heartbeat.sh` | ST-01 | SAPI heartbeat to NCP; flags timeouts |
| `st01_analyze.sh`   | ST-01 | TRANSMIT_COMPLETE_OK / SendDataBridge ratio in ZGW log + heartbeat-timeout count |

`tests/stress/07_run.sh` will start the heartbeat in the background
before the load loop and call the analyzer once the load stops.
