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

| File | Test | Signal |
|------|------|--------|
| `st01_heartbeat.sh` | ST-01 | mDNS (`avahi-resolve`) liveness probe of ZGW from `[test-controller]`; one timestamped CSV row per sample, `status` in {ok,fail,timeout} |
| `st01_analyze.sh`   | ST-01 | post-run: heartbeat-timeout streak (reliable) + ZGW-log tx-marker gap (corroborating) -> `verdict.txt` + `summary.json` |
| `st02_tailer.sh`    | ST-02 | live tail of remote ZGW log; on `Node N is now failing`, mDNS resolve `zw<HomeID><NNNN>.local` then ping (default is 30s timeout); CSV row per event |
| `st02_analyze.sh`   | ST-02 | post-run wrapper: runs `st02_bucket.awk` |
| `st03_zgw_probe.sh` | ST-03 | mDNS (`avahi-resolve`) liveness probe of the ZGW controller resource. Similar to ST-01. TODO: check if it worth the duplication |
| `st03_analyze.sh`   | ST-03 | post-run: PID alive/unchanged at run end + every probe row ok + zero fatal-keyword matches in `zipgateway.log` |
