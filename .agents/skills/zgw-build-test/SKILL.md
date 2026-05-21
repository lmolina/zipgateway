---
name: zgw-build-test
description: Build and run zipgateway (zw-zgw) targets and unit tests inside the Debian-Stretch dev Docker container. Supports both i386 (default, faster) and arm32v7/armhf. Use when the user asks to build the project, run ctest, run a specific unit test target, or verify a change in zw-zgw. The host toolchain cannot build this project; all compilation and ctest runs must happen inside the dev container.
disable-model-invocation: true
---

# zw-zgw build and test

## Why this skill exists

`zw-zgw` is a 32-bit Z/IP Gateway pinned to **Debian Stretch** (Debian 9, EoL):
- Pinned gcc/glibc versions. Modern gccs fail on unrelated
  `-Werror=stringop-overread` warnings.
- Pinned runtime deps (libssl 1.1, libjson-c2/3/4, parprouted, radvd) packaged for
  Stretch.
- The Debian package built here is shipped against that baseline.

Two architectures are supported, both running Debian Stretch in the container:

| Arch | Debian arch | Docker image base | When to use |
|------|-------------|-------------------|-------------|
| `i386` | `i386` | `docker.io/i386/debian:stretch` | **Default.** Native on x86_64 hosts, much faster. Use unless you specifically need ARM. |
| `arm32v7` | `armhf` | `docker.io/arm32v7/debian:stretch` | Reproduces the Raspberry Pi target. Required when validating ARM-specific behavior or packaging the `armhf` `.deb`. Runs under qemu on x86_64 hosts and is significantly slower. |

The container bind-mounts the repo at `/usr/local/src/zipgateway`. That path is
baked into `build/CMakeCache.txt`, so always build from inside the container.
Use a per-arch build directory to keep caches separate.

## Prerequisites

- Docker running on the host.
- Run commands from the repository root.
- `docker compose` (v2). The repo's `docker-compose.yml` defines a `dev` service.
- **For `arm32v7` only:** `qemu-user-static` and `binfmt-support` registered on
  the host so the kernel can execute ARM binaries transparently. On
  Debian/Ubuntu hosts the package names match; CI does this in
  `.github/workflows/build.yml`.

## Architecture selection

Two environment variables drive the build. Set them together; image and
container names follow `ARCH`:

| `ARCH` | `TARGET_DEBIAN_ARCH` | Image tag | Suggested container name |
|--------|----------------------|-----------|--------------------------|
| `i386` | `i386` | `zipgateway-dev-i386` | `zgw-dev-i386` |
| `arm32v7` | `armhf` | `zipgateway-dev-arm32v7` | `zgw-dev-arm32v7` |

Distinct container names let both architectures coexist on the same host.
Each arch must use its own build directory (`build/` for i386,
`build-arm32v7/` for ARM) -- they are not interchangeable.

## Workflow

The examples below use `i386` (the default). To target ARM, substitute
`ARCH=arm32v7 TARGET_DEBIAN_ARCH=armhf` and use the matching container name
and a separate build directory (e.g. `build-arm32v7`).

### 1. Ensure a dev container is running

Check first (replace tag for the arch you want):

```bash
docker ps --format '{{.Names}} {{.Image}}' | grep zipgateway-dev-i386
```

If nothing matches, start a detached container. The container name should
include the arch to allow both to coexist:

i386 (default):

```bash
ARCH=i386 TARGET_DEBIAN_ARCH=i386 \
  docker compose run -d --name zgw-dev-i386 dev sleep infinity
```

arm32v7 (only when ARM is required):

```bash
ARCH=arm32v7 TARGET_DEBIAN_ARCH=armhf \
  docker compose run -d --name zgw-dev-arm32v7 dev sleep infinity
```

Subsequent commands target the container with `docker exec <name>`.

### 2. Configure the build (first time, or when CMakeLists changes)

Use a per-arch build directory so caches do not collide.

```bash
# i386
docker exec zgw-dev-i386 bash -lc 'mkdir -p build && cd build && cmake ..'

# arm32v7
docker exec zgw-dev-arm32v7 bash -lc 'mkdir -p build-arm32v7 && cd build-arm32v7 && cmake ..'
```

Repeat after adding/removing test targets in any `CMakeLists.txt`.

### 3. Build a specific target

Prefer building a single target rather than the whole project (faster, avoids
unrelated breakage):

```bash
# i386
docker exec zgw-dev-i386 bash -lc 'cmake --build build --target <target_name> -j'

# arm32v7
docker exec zgw-dev-arm32v7 bash -lc 'cmake --build build-arm32v7 --target <target_name> -j'
```

Examples:

- Test binary: `--target test_serialapi`
- Library: `--target zipgateway-lib`
- All: omit `--target`.

### 4. Run tests

Run a single test:

```bash
# i386
docker exec zgw-dev-i386 bash -lc 'cd build && ctest -R <test_name_regex> -V'

# arm32v7
docker exec zgw-dev-arm32v7 bash -lc 'cd build-arm32v7 && ctest -R <test_name_regex> -V'
```

Run all tests:

```bash
docker exec zgw-dev-i386 bash -lc 'cd build && ctest --output-on-failure'
```

`-V` prints the full Unity output (per-assertion). `--output-on-failure` is quieter
and only shows logs for failing tests. Expect ARM runs to be noticeably slower
under qemu.

### 5. Iterate

After editing source on the host, the bind mount makes changes immediately visible
inside the container. Re-run step 3 (build) and step 4 (test). No restart needed.

## Common pitfalls

- **`build-host/` exists on the host.** That's a stale attempt to build natively.
  Ignore it. Use `build/` (i386) or `build-arm32v7/` (ARM) from inside the
  container.
- **`CMakeCache.txt` complains about source paths.** The cache was generated
  inside the container at `/usr/local/src/zipgateway`. If you accidentally ran
  `cmake` from the host, delete the offending `CMakeCache.txt` and re-configure
  inside the container.
- **Mixing arches in the same build directory.** The two arches' caches are
  incompatible. Use `build/` only for i386 and a separate directory (e.g.
  `build-arm32v7/`) for ARM.
- **`add_unity_test` runner regeneration.** Adding tests in a new test file
  requires re-running `cmake` (step 2), not just `cmake --build`. The runner
  generator only re-scans test files at configure time.
- **`if (NOT APPLE)` guards.** Several `test/*/CMakeLists.txt` skip tests on
  Apple. The dev container is Linux, so they run.
- **Missing `binfmt-support` on the host.** `arm32v7` containers fail to start
  ARM binaries with `exec format error`. Install
  `qemu-user-static binfmt-support` and verify with
  `docker run --rm arm32v7/debian:stretch uname -m` (expect `armv7l`).

## Quick reference

```bash
# Default: i386 ----------------------------------------------------------
ARCH=i386 TARGET_DEBIAN_ARCH=i386 \
  docker compose run -d --name zgw-dev-i386 dev sleep infinity

docker exec zgw-dev-i386 bash -lc 'mkdir -p build && cd build && cmake ..'
docker exec zgw-dev-i386 bash -lc 'cmake --build build --target test_serialapi -j'
docker exec zgw-dev-i386 bash -lc 'cd build && ctest -R test_serialapi -V'
docker rm -f zgw-dev-i386

# ARM: arm32v7 / armhf ---------------------------------------------------
ARCH=arm32v7 TARGET_DEBIAN_ARCH=armhf \
  docker compose run -d --name zgw-dev-arm32v7 dev sleep infinity

docker exec zgw-dev-arm32v7 bash -lc 'mkdir -p build-arm32v7 && cd build-arm32v7 && cmake ..'
docker exec zgw-dev-arm32v7 bash -lc 'cmake --build build-arm32v7 --target test_serialapi -j'
docker exec zgw-dev-arm32v7 bash -lc 'cd build-arm32v7 && ctest -R test_serialapi -V'
docker rm -f zgw-dev-arm32v7
```
