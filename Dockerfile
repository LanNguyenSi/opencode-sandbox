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

ENV PATH="/root/.opencode/bin:$PATH"

WORKDIR /workspace

ENTRYPOINT ["opencode"]
