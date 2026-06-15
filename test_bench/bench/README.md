<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# Bench (shared library)

Shared bring-up logic for all tests in this repository. Each test under
`tests/<name>/` owns its own numbered `0N_*.sh` scripts that call into
this directory, plus its own `conf` and `bed.tsv`.

## Contract

Every script in this directory expects the caller to export `TEST_DIR`
pointing at the test directory that owns the run, e.g.

```bash
export TEST_DIR=/abs/path/to/tests/endurance
exec /abs/path/to/bench/fetch_artifacts.sh
```

The bench script then sources `${TEST_DIR}/conf` (which sets
`BED_TSV=${TEST_DIR}/bed.tsv` via `dirname`) and resolves shared
helpers from `${0%/*}/utils.sh`. The thin wrappers under
`tests/<name>/` already do this.

## Contents

| File | Role |
|------|------|
| `utils.sh` | `bed_load`, board power helpers, artifact path helpers, `run_dir_attach`, `bed_node_uri` |
| `init_test_run.sh` | step 00: `mkdir` the run folder (fails if it exists), drop a manifest |
| `fetch_artifacts.sh` | wget unique URLs from `${TEST_DIR}/bed.tsv` into repo-root `artifacts/` |
| `prepare_boards.sh` | flash boards, write `artifacts/dsks`, power off |
| `setup_zipgateway.sh` | rsync ZGW `.deb` to `[zgw-host]`, cleanup, reinstall, reboot |
| `provisioning.sh` | SSH driver: stage workers + dsks, run SmartStart, pull logs into `${STEP_DIR}` |
| `provision_on_host.sh` | SmartStart worker on `[zgw-host]`; invoked by `provisioning.sh` |
| `inclusion.sh` | step 05 driver: power-cycle each device in slot order |
| `zgw_cleanup.sh` | purge/reinstall ZGW on `[zgw-host]` |
| `power_off_all_boards.sh` | manual recovery: power off every slot in `${TEST_DIR}/bed.tsv` |

Run a test from its directory, e.g.
`cd tests/endurance && ./00_init_test_run.sh run_<test_name> && ./01_fetch_artifacts.sh ./run_<test_name>`.
