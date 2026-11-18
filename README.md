# Nightshift harness

The tools a [Nightshift](https://github.com/mobiuscode-com) run needs to drive its coding agent, in an image
`FROM scratch`. The Nightshift runner mounts it read-only at `/nightshift/tools` into whatever image a project works in,
so a project image needs no harness of its own, and a harness upgrade needs no project image to be rebuilt.

```sh
docker pull ghcr.io/mobiuscode-com/nightshift-harness:<version>
```

| Path | What it is |
|---|---|
| `/nightshift/tools/node` | Node.js, called by absolute path only — a run's own `PATH` and Node stay untouched |
| `/nightshift/tools/pi` | the full npm install of [Pi](https://github.com/earendil-works/pi-coding-agent), from `package-lock.json` |
| `/nightshift/tools/bin/pi` | wrapper: this Node + Pi |
| `/nightshift/tools/bin/codebase-memory-mcp` | [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp), the code-graph MCP server, static |

The image cannot run on its own. A runner names it with `NIGHTSHIFT_HARNESS_IMAGE` and mounts it with
`--mount type=image,…,image-subpath=nightshift/tools` (Docker Engine 28+), or copies it into a named volume once.

## What a project image needs

The tools are not fully static: the official Node build is glibc-only. A project image has to offer linux/amd64 or
arm64, **glibc** (Alpine images do not work), a POSIX `sh`, `git`, `tar` and CA certificates. The runner checks all of
it before a run starts. [nightshift-agent](https://github.com/mobiuscode-com/nightshift-agent) is the default image and
a good base for your own.

## Versions

Releases follow [Semantic Versioning](https://semver.org) and are made automatically from the commit messages
([Conventional Commits](https://www.conventionalcommits.org): `feat:` a minor release, `fix:`/`perf:` a patch, a
breaking change a major; `chore`, `docs`, `refactor`, `style` and `test` release nothing). Every release is pushed as
`<version>`, `<major>.<minor>`, `<major>` and `latest`, for linux/amd64 and linux/arm64.

Pin an exact version on your runners. Docker only pulls an image it does not have, so a moving tag like `latest` stays
whatever a machine pulled first. The runner writes Pi's configuration, so a release that changes what Pi expects is a
**breaking change** here, and the Nightshift runner pins the harness version it was tested with.

## Building

```sh
docker build -t nightshift-harness:dev .
```

Every download is pinned by version **and** checksum; change both together. Pi's version moves only through
`package.json` and a regenerated lockfile (`npm install --package-lock-only`). The build runs Pi once and loads its
image module (`@silvia-odwyer/photon-node`), without which Pi silently drops every image input — so such an install
fails the build instead.

Nightshift's end-to-end test runs real Pi from this image against a scripted model; run it after every change here
(see Nightshift's `AGENTS.md`, `PiEndToEndTest`).
