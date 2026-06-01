FROM ubuntu:24.04

# Why ubuntu:24.04 and not the upstream ghcr.io/anomalyco/opencode image?
# Upstream ships an Alpine (musl) image, but bundles a glibc-linked OpenTUI
# render library since v1.15.x. dlopen fails on `ld-linux-x86-64.so.2`, the
# TUI never renders, the process hangs. Tracked at
# https://github.com/anomalyco/opencode/issues/28070. A glibc base avoids it.

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates git unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://opencode.ai/install | bash

# Token-usage reporting (opencode-sandbox --usage) shells out to tokscale, a
# Node CLI. opencode ships as a single static binary with no JS runtime, so we
# add bun and install tokscale globally. A tiny shim runs the node-shebang
# tokscale binary under bun.
RUN curl -fsSL https://bun.sh/install | bash

ENV PATH="/usr/local/bin:/root/.bun/bin:/root/.opencode/bin:$PATH"

RUN bun install -g tokscale@3.0.0

RUN printf '#!/bin/sh\nexec bun /root/.bun/bin/tokscale "$@"\n' > /usr/local/bin/tokscale \
    && chmod +x /usr/local/bin/tokscale

WORKDIR /workspace

ENTRYPOINT ["opencode"]
