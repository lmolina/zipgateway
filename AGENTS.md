# AGENTS.md -- Z/IP Gateway (zipgateway)

> Single source of truth for AI coding agents working in this repo.
> Read natively by Cursor, Codex, Copilot, Gemini, Windsurf; Claude
> Code loads it via its own loader. ASCII only.

---

## Project posture

- **Maintenance mode.** The supported successor is
  [z-wave-protocol-controller](https://github.com/SiliconLabsSoftware/z-wave-protocol-controller)
  (see [README.md](./README.md) disclaimer).
- Z-Wave protocol behavior, S2 security, and certification-relevant
  outputs are **invariants**. Treat changes that affect them as
  high-risk until proven otherwise.
- Default to the smallest, proven, reversible change. When in doubt,
  ask the user before acting.

---

## Change discipline

- **TDD:** write a failing test (RED), make the minimum change to
  pass (GREEN), then commit. No fix lands without a test that would
  have caught the bug.
- **Fix the root cause, not the symptom.** Symptom-only patches are
  rejected. If the root cause is out of scope, stop and report.
- **Atomic commits.** One logical change per commit; each commit
  independently revertible and passing tests on its own.
- **Refactors go in a separate, follow-up commit.** Never bundle a
  refactor with a fix or a feature.
- Tests must pass before commit. Stage files explicitly; do **not**
  use `git add -A`.
- Do **not** force-push shared branches. Do **not** pass
  `--no-verify` without explicit user request.

---

## Commit messages

- Conventional Commits: `type(scope): subject`.
- Subject: imperative, <= 72 chars. Body: explain the **why**, not
  the what.
- Types in use here: `feat`, `fix`, `test`, `refactor`, `perf`,
  `chore`, `docs`.

Examples from this repo's history:

```
fix(s2): widen mc_state node IDs to nodeid_t
test(sapi): avoid time-based false negatives in test_serialapi
```

---

## Repository layout

| Path | What it is |
|------|------------|
| `src/` | Main gateway sources. |
| `test/` | Unit tests (Unity + CMock). |
| `libs2/` | Vendored Z-Wave S2 security library (Apache 2.0). |
| `libzwaveip/` | Vendored Z-Wave IP library + reference client (Apache 2.0). |
| `contiki/` | Vendored Contiki OS 2.4, heavily modified. |
| `sqlite/` | Vendored SQLite amalgamation. |
| `systools/` | CLI utilities (programmer, restore, etc.). |
| `cmake/` | Toolchain files and CMake helpers. |
| `files/` | Runtime configs, init scripts, deb packaging scripts. |
| `doc/` | Diagrams and release notes. |
| `DevTools/` | Off-target build helpers. |
| `.github/workflows/` | CI (see `build.yml`). |
| `.agents/skills/` | Agent-invocable skills (this file's companions). |

---

## Build and test

- The gateway is **32-bit** (i386) and requires Debian Stretch. A native
  x86_64 host cannot build it; use the dev container.
- Entry points: [Dockerfile](./Dockerfile),
  [docker-compose.yml](./docker-compose.yml),
  [helper.mk](./helper.mk).
- Detailed workflow (start container, configure cmake, build a
  target, run ctest): see
  [.agents/skills/zgw-build-test/SKILL.md](./.agents/skills/zgw-build-test/SKILL.md).

CI runs the multi-stage Docker build defined in
[.github/workflows/build.yml](./.github/workflows/build.yml); a green
local container build is the strongest local signal before pushing.

---

## Skills

Active skills live under `.agents/skills/<name>/SKILL.md` with YAML
frontmatter (`name`, `description`). Invoke by name when the
description matches the task.

---

## Never do without explicit user go-ahead

- Modify vendored code: `contiki/`, `sqlite/`. Patch upstream-style only when
  there is no alternative, and document why.
- Disable, skip, or `#ifdef`-out a failing test to make CI green.
- Change security-critical paths (S2, DTLS, key management, Mailbox
  flow control, Network Management FSM) without an accompanying
  unit test that exercises the change.
- Opportunistic reformatting, renaming, or restyling outside the
  scope of the change.
- Run privileged commands (`sudo`, `apt`, `dpkg`, `systemctl`) on
  the user's behalf.

---

## Verify before suggesting

- Inspect actual code, headers, and `CMakeLists.txt` in this tree
  before proposing an API or a build flag. Do not rely on memory or
  external docs alone.
- For any production change, confirm an existing unit test covers
  the touched path, or add one as part of the change.

---

## Reference

- [README.md](./README.md) -- install, run, examples.
- [Dockerfile](./Dockerfile),
  [docker-compose.yml](./docker-compose.yml),
  [helper.mk](./helper.mk) -- build/test entry points.
- [.github/workflows/build.yml](./.github/workflows/build.yml) -- CI.
