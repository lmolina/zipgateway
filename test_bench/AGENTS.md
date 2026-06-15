<!-- SPDX-FileCopyrightText: Silicon Laboratories Inc. <https://www.silabs.com/> -->
<!-- SPDX-License-Identifier: LicenseRef-MSLA -->

# AGENTS.md -- zgw-test-bench

Shared agent context for this repo. Self-contained: a coworker or AI agent
should be able to operate the repo with only this file plus
`tests/endurance/README.md` (the step-by-step). Personal planning state
(per-collaborator focus, backlog, journal) lives outside this repo.

## What this repo is

Test bench for Z/IP Gateway (ZGW). Phases:

- Phase 1 (current): endurance test. A long-duration burst-traffic load
  against ZGW on testbed-1 (see `tests/endurance/bed.tsv`), run via
  `tests/endurance/`.
- Phase 2: FT-01..FT-08 functional tests (different bed; deferred).
- Phase 3+: stress / endurance suite expansion; UTF integration evaluation.

The test specification proper is on
[Confluence](https://confluence.silabs.com/spaces/ZWAVE/pages/801038048/Z+IP+Gateway+Test+Plan).
This repo owns the *implementation* of those tests, not their definition.

## Layout

```
bench/              shared bring-up (neutral filenames; no step order)
tests/endurance/    endurance test (numbered 01..04, 07 define the order)
tests/stress/       stress test (same pattern; checks under checks/)
artifacts/          input binaries + intermediate dsks (gitignored)
```

Each test's numbered scripts compose `bench/`. The 9-step endurance
walkthrough lives in `tests/endurance/README.md`.

## Hardware bed (two hosts)

- `[test-controller]`  developer machine. Runs Simplicity Commander,
                       downloads CI artifacts, flashes radio boards
                       over JLink-IP.
- `[zgw-host]`         RPi running `zipgateway` and `reference_client`.
                       Currently `<ZGW_HOST>`.

Network addresses, ZGW PSK, and per-device routes live in each test's
`conf` and `bed.tsv` (e.g. `tests/endurance/conf`).

## Scripts

Endurance step scripts (run from `tests/endurance/`):

```
tests/endurance/
  00_init_test_run.sh      [test-controller]  -> bench/init_test_run.sh
  01_fetch_artifacts.sh    [test-controller]  -> bench/fetch_artifacts.sh
  02_prepare_boards.sh     [test-controller]  -> bench/prepare_boards.sh
  03_setup_zipgateway.sh   [test-controller]  -> bench/setup_zipgateway.sh
  04_provisioning.sh       [test-controller]  -> bench/provisioning.sh
  05_inclusion.sh          [test-controller]  -> bench/inclusion.sh
  07_run.sh                [test-controller]  endurance load (stages run_on_host.sh)
```


`03_setup_zipgateway.sh` requires SSH key-based access plus passwordless
`sudo` for `${ZGW_USER}` on `[zgw-host]`. It is the only sanctioned way
to mutate `[zgw-host]` from the bench scripts.

## Run folder convention

One folder per test run, with one subfolder per step. Single identifier
plumbed identically across controller wrappers, bench/ helpers, and
zgw-host workers:

| Variable | Set by | Meaning |
|---|---|---|
| `RUN_DIR` | First positional arg to every numbered script | Run-root path (controller path on controller, zgw-host path on worker) |
| `RUN_REMOTE_DIR` | Controller wrappers driving an SSH worker | `${ZGW_STAGE_DIR}/$(basename ${RUN_DIR})` (zgw-host path) |
| `STEP_DIR` | Each step computes locally | `${RUN_DIR}/<step_name>` |
| `STEP_REMOTE_DIR` | Controller wrappers driving an SSH worker | `${RUN_REMOTE_DIR}/<step_name>` |

Workers receive `RUN_DIR` over SSH and compute their own `STEP_DIR`,
identical to controller scripts. Step subfolder names match the script
basename: `01_fetch_artifacts`, `02_prepare_boards`, `03_setup_zipgateway`,
`04_provisioning`, `05_inclusion`, `07_run`. Stress verdict files (`verdict.txt`,
`summary.json`) sit at the run root because the verdict is for the whole
test run, not a single step.

Bench utilities:

- `bench/utils.sh`               sourced by every script
- `bench/zgw_cleanup.sh`         runs on [zgw-host], invoked by setup_zipgateway
- `bench/power_off_all_boards.sh`  manual recovery

## Configuration

Each test owns its own `conf` and `bed.tsv` under `tests/<name>/`
(same syntax across tests, swappable). `tests/<name>/conf` mixes:

- machine-specific facts: zgw-host hostname, ZGW PSK, REGION (default
  RF region used by the gateway and as `bed.tsv` fallback), ZGW install path.
- test parameters: `BURST_SIZE`, burst sleep, wake-up interval,
  command-class hex strings.

The thin wrappers under `tests/<name>/` export `TEST_DIR` (the test's
own directory) before exec'ing into `bench/`; `bench/` scripts then
source `${TEST_DIR}/conf`. This is the contract any new test under
`tests/` must follow.

`tests/<name>/bed.tsv` is the per-device description (JLink-IP, board,
device, role, route, region, firmware, bootloader). It is loaded by
`bed_load` in `bench/utils.sh`. Bootloader and firmware columns hold
full Artifactory URLs; `fetch_artifacts.sh` wget's each unique URL
into repo-root `artifacts/` mirroring the path after `/artifactory/`.
Splitting the rest of `conf` into machine vs test config is a backlog
item.

## Artifacts

- `artifacts/`  INPUT.  CI binaries (`*.s37`, `*.hex`) and the ZGW `.deb`.
                Gitignored except for `.gitkeep` and `README.md`. The
                ZGW `.deb` is dropped manually (Simplicity Studio export
                or CI build); the radio binaries are downloaded by
                `01_fetch_artifacts.sh`.
- `tests/<name>/run_*/`   OUTPUT. One folder per test run. Each step writes
                into its own subfolder.
- `artifacts/dsks`        OUTPUT (intermediate). Generated by
                `02_prepare_boards.sh`, consumed by `04_provisioning.sh`.

## Conventions

- ASCII only in code, docs, comments, commit messages.
- Conventional commits, atomic, each commit complete and tests pass.
  Commit message focuses on the *why*; the *what* is the diff.
- Explicit `git add <path>` -- never `-A` or `.`.
- No force-push, no rewriting pushed history.
- The 9-step flow is manual orchestration.
- Lean / iterative / MVP first. Add complexity only when justified.

## Quality gates

Run `pre-commit install` once per checkout. Hooks currently include
trailing-whitespace, end-of-file-fixer, mixed-line-ending,
check-merge-conflict, and reuse lint. Never bypass with `--no-verify`.

## What an AI agent must NOT do

- Run `sudo` or `apt` on `[test-controller]` without explicit user approval.
- Mutate `[zgw-host]` outside of `03_setup_zipgateway.sh` (which is the
  only sanctioned automation path; ad-hoc SSH changes still require
  explicit user approval).
- Commit run output (`tests/<name>/run_*/`, `dsks`, `*.zlf`).
- Commit input binaries (`artifacts/*` except `.gitkeep` and `README.md`).
- Bypass pre-commit with `--no-verify`.
- Edit this file without explicit user approval.

## Skills

None yet. Trigger: when a multi-step recipe is being repeated by an
agent or coworker more than twice, promote it to
`.agents/skills/<name>/SKILL.md` (shared across collaborators). First likely
candidate: `bring-up-endurance-bed` (the 9-step flow as an
agent-runnable recipe).
