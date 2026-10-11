# Architecture

How `opencode-sandbox` resolves a workspace, builds its image, and runs OpenCode in a container.

## Flow

A single invocation resolves the workspace, ensures the image exists, runs OpenCode in an isolated container, and, with the default image and auto-usage on, prints a token-usage summary on exit. `--usage` and `--print` exit early.

The first diagram shows startup and the two early exits; the second continues from the state directory through image acquisition and the run.

```mermaid
flowchart TD
    A["parse options"] --> B["resolve workspace root<br/>git rev-parse --show-toplevel / pwd"]
    B --> C["WORKSPACE_SLUG<br/>HOST_OPENCODE_HOME = ~/.opencode-home/slug"]
    C --> D{"docker on PATH?"}
    D -- no --> D1["error, exit 1"]
    D -- yes --> U{"--usage?"}
    U -- yes --> UM["run_usage_mode()<br/>tokscale container, state :ro"]
    U -- no --> P{"--print?"}
    P -- yes --> PO["print docker command(s), exit 0"]
    P -- no --> M["--init-structure dirs<br/>mkdir state dir"]
```

```mermaid
flowchart TD
    M["--init-structure dirs<br/>mkdir state dir"] --> PL{"--pull?"}
    PL -- "yes, default image" --> F1["build_local_image()<br/>--pull --no-cache"]
    PL -- "yes, OPENCODE_IMAGE" --> F2["docker pull"]
    PL -- no --> E{"default image<br/>missing locally?"}
    E -- yes --> F3["build_local_image()"]
    E -- no --> AU{"auto-usage on<br/>and default image?"}
    F1 --> AU
    F2 --> AU
    F3 --> AU
    AU -- yes --> H["docker run OpenCode<br/>capture exit code"]
    H --> J["print_usage_after_run()<br/>second tokscale container, state :ro"]
    J --> R["exit with OpenCode's code"]
    AU -- no --> X["exec docker run OpenCode<br/>(no summary)"]
```

## Workspace resolution

If the current directory is inside a Git repository, the wrapper uses `git rev-parse --show-toplevel` as the workspace root; otherwise it uses the current directory. Git is optional: a non-Git directory works the same way, just without that auto-detection step.

## Per-workspace state and isolation

OpenCode state (auth tokens, session history) lives on the host under `~/.opencode-home/<slug>/`, where `<slug>` is the workspace directory's basename, lowercased, with each run of characters outside `a-z0-9_.-` replaced by a single `-` and any leading or trailing `-` removed (`workspace` if nothing is left), followed by `-` and the first 8 hex characters of the SHA-256 of its absolute path (`opencode-sandbox`'s `sha256_hex()` / `WORKSPACE_SLUG`). Only the basename is human-readable; the full path is not encoded. That directory is mounted as the container's `HOME`.

This is the wrapper's isolation boundary between projects: two different directories that happen to share a basename (for example `~/work/api` and `~/play/api`) get distinct state dirs because the slug includes a hash of the full path, so their auth tokens and session history never mix. The basename alone would not be enough to prevent that collision, which is why the hash is there (see [Troubleshooting](troubleshooting.md) for the pre-hash legacy layout).

## Container boundaries

The diagram shows which host paths each container mounts and which containers can reach the network. The OpenCode container and the tokscale usage container (`--usage` and the post-run summary) are separate `docker run` invocations.

```mermaid
flowchart TD
    subgraph host ["Host"]
        WS["workspace root"]
        ST[("~/.opencode-home/slug")]
        ROOT[("~/.opencode-home")]
        SET["temp settings.json<br/>(--usage --all)"]
    end
    OC["OpenCode container"]
    UC["tokscale usage container<br/>--usage / post-run summary"]
    NET(("network"))
    WS -- "rw /workspace" --> OC
    ST -- "rw /opencode-home (HOME)" --> OC
    ST -- "ro /data" --> UC
    ROOT -- "ro /data (--usage --all)" --> UC
    SET -- "ro" --> UC
    OC -.->|"unless --offline"| NET
    UC -- "always" --> NET
```

- The current workspace is mounted read-write at `/workspace`; the container has no access to the rest of the host filesystem beyond that mount and the per-workspace state directory.
- `--offline` runs the OpenCode container with `--network none`. The post-run usage summary and `--usage` run in a separate container that keeps networking (tokscale refreshes model pricing) and mounts the workspace's OpenCode state read-only. If no container should reach the network, add `--no-usage` (or `OPENCODE_NO_USAGE=1`) to skip the post-run summary and do not run `--usage`. `--offline` does not cover image acquisition: build or pull the image beforehand, because a first-run build of the default image, or an `OPENCODE_IMAGE` that is not present locally, still reaches the network.
- The default image is built locally from the embedded Dockerfile, but the build itself reaches external sources: it pulls `ubuntu:24.04` from Docker Hub, installs `curl`, `ca-certificates`, `git`, and `unzip` from the Ubuntu package archive, pipes the upstream `opencode.ai/install` and `bun.sh/install` scripts (not version-pinned) into `bash`, and installs `tokscale@3.0.0` from the npm registry. `--pull` rebuilds with `docker build --pull --no-cache`. Setting `OPENCODE_IMAGE` replaces all of this with the named registry image.
- OpenCode runs as root inside the container: the image sets no `USER` and the wrapper passes no `--user` (the reference Compose service sets no `user:` either). With a rootful Docker Engine on Linux, files it creates in the workspace or in `~/.opencode-home/<slug>/` are owned by root on the host; see [Troubleshooting](troubleshooting.md#files-in-the-workspace-or-state-directory-are-owned-by-root-linux).
- The wrapper passes only `HOME=/opencode-home` and `TERM` to the OpenCode container; other host environment variables, including provider API keys, are not forwarded (see [Configuration](configuration.md#environment-variables)).
- The wrapper does not expose the Docker socket into the container, so OpenCode running inside it cannot itself launch further containers on the host.

`--usage --all` additionally mounts the whole `~/.opencode-home` read-only so usage can be aggregated across workspaces.

## Why a local Ubuntu (glibc) image

The upstream `ghcr.io/anomalyco/opencode` image is Alpine (musl), but OpenCode bundles a glibc-linked OpenTUI render library. On that image the TUI fails to initialize with `Error loading shared library ld-linux-x86-64.so.2` and the process hangs with a blank terminal. Building locally from `ubuntu:24.04` avoids it. See [anomalyco/opencode#28070](https://github.com/anomalyco/opencode/issues/28070).
