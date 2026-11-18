# syntax=docker/dockerfile:1.7
#
# The Nightshift harness image: everything a Nightshift run needs to drive its agent, under /nightshift/tools, in an
# image FROM scratch. The Nightshift runner mounts it read-only into the project's own image
# (`--mount type=image,...,image-subpath=nightshift/tools`), so a project image needs no harness of its own and a harness
# upgrade needs no project to rebuild. Version it, and pin it on the runners (`nightshift.runner.harness-image`).
#
#   /nightshift/tools/node                 Node.js, called by absolute path — the run's PATH and Node stay untouched
#   /nightshift/tools/pi                   Pi's full npm install (npm ci from package-lock.json)
#   /nightshift/tools/bin/pi               wrapper: our Node + Pi
#   /nightshift/tools/bin/codebase-memory-mcp   the code graph, static
#
# The project image needs glibc, a POSIX shell, git, tar and CA certificates (the official Node build is glibc-only).
# Built from the repository root: docker build -t nightshift-harness .

ARG TEMURIN_IMAGE=eclipse-temurin:25.0.4.1_1-jdk-noble

FROM ${TEMURIN_IMAGE} AS fetch
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl xz-utils gnupg \
 && rm -rf /var/lib/apt/lists/*
# `sha512 <base64 digest> <file>`: npm publishes its integrity as base64, sha512sum wants hex.
RUN printf '%s\n' '#!/bin/sh' 'set -eu' \
      'echo "$(printf %s "$1" | base64 -d | od -An -v -tx1 | tr -d " \n")  $2" | sha512sum -c -' \
      > /usr/local/bin/sha512-b64 \
 && chmod +x /usr/local/bin/sha512-b64

# Node.js, only for Pi: it is called by absolute path and never on a run's PATH, so it needs to suit Pi and nothing
# else. Moving it changes this ARG and both checksums together. Checksums from
# https://nodejs.org/dist/v<version>/SHASUMS256.txt.
FROM fetch AS node
ARG TARGETARCH
ARG NODE_VERSION=24.13.0
ARG NODE_SHA256_AMD64=e798599612f4bb71333a3397ab0d095fd62214e115aea45aa858a145fc72d67e
ARG NODE_SHA256_ARM64=aa881151bd0f9f154a0424dd60a72e9ce10672619121658c278a24327ef46831
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) arch=x64;   sum="$NODE_SHA256_AMD64" ;; \
      arm64) arch=arm64; sum="$NODE_SHA256_ARM64" ;; \
      *) echo "unsupported architecture $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/node.tar.xz "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-$arch.tar.xz"; \
    echo "$sum  /tmp/node.tar.xz" | sha256sum -c -; \
    mkdir /node; \
    tar -xJf /tmp/node.tar.xz -C /node --strip-components=1 --no-same-owner

# codebase-memory-mcp, the code-graph MCP server of the agents' Pi sessions (registered per run by the Nightshift
# runner). The -portable archives are fully static. Checksums from
# https://github.com/DeusData/codebase-memory-mcp/releases/download/v<version>/checksums.txt.
FROM fetch AS codebase-memory
ARG TARGETARCH
ARG CBM_VERSION=0.12.1
ARG CBM_SHA256_AMD64=8c3d0341064301e78ecc84cf7348d4e2c6562a0f57448243ea560aaa34de36c1
ARG CBM_SHA256_ARM64=ed0f1f548cd79b121c401c2e9f7841c189a001af26d3768368088c24f6a53533
RUN set -eu; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
      amd64) sum="$CBM_SHA256_AMD64" ;; \
      arm64) sum="$CBM_SHA256_ARM64" ;; \
      *) echo "unsupported architecture $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/cbm.tar.gz \
      "https://github.com/DeusData/codebase-memory-mcp/releases/download/v$CBM_VERSION/codebase-memory-mcp-linux-$arch-portable.tar.gz"; \
    echo "$sum  /tmp/cbm.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/cbm.tar.gz -C /tmp codebase-memory-mcp; \
    install -m 0755 /tmp/codebase-memory-mcp /codebase-memory-mcp

FROM fetch AS tools
COPY --from=node /node /nightshift/tools/node
COPY package.json package-lock.json /nightshift/tools/pi/
COPY --from=codebase-memory /codebase-memory-mcp /nightshift/tools/bin/codebase-memory-mcp
# The full install, not Pi's bare bundle: image input needs @silvia-odwyer/photon-node from node_modules, and without it
# Pi silently replaces every image by "(image omitted)". The smoke test below is what catches that.
RUN set -eu; \
    cd /nightshift/tools/pi; \
    PATH=/nightshift/tools/node/bin:$PATH npm ci --omit=dev --no-audit --no-fund; \
    printf '%s\n' '#!/bin/sh' \
      'exec /nightshift/tools/node/bin/node /nightshift/tools/pi/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js "$@"' \
      > /nightshift/tools/bin/pi; \
    chmod 0755 /nightshift/tools/bin/pi; \
    /nightshift/tools/bin/pi --version; \
    /nightshift/tools/node/bin/node -e "require('/nightshift/tools/pi/node_modules/@silvia-odwyer/photon-node')"; \
    /nightshift/tools/bin/codebase-memory-mcp --version >/dev/null 2>&1 || /nightshift/tools/bin/codebase-memory-mcp --help >/dev/null

FROM scratch
ARG APP_VERSION=dev
LABEL org.opencontainers.image.title="Nightshift harness" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.source="https://github.com/mobiuscode-com/nightshift-harness"
COPY --from=tools /nightshift/tools /nightshift/tools
