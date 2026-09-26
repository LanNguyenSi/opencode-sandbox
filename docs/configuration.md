# Configuration

Full reference for `opencode-sandbox`'s flags, environment variables, and the reference `docker-compose.yml`.

## Wrapper options

```text
Usage: opencode-sandbox [wrapper-options] [--] [opencode-args...]

Wrapper options:
  --offline           Disable container networking
  --pull              For the default local image, rebuild it from the embedded
                      Dockerfile (via docker build --pull --no-cache). For an
                      OPENCODE_IMAGE override, runs docker pull.
  --print             Print the docker command and exit without changing the workspace
  --init-structure    Create tasks/, context/, tmp/, outputs/ in workspace
  --usage             Report token usage and cost for this workspace and exit.
                      Combine with --all to aggregate across all workspaces, or
                      pass tokscale flags through (e.g. --usage --json, --today).
  --all               With --usage, aggregate across every workspace under
                      ~/.opencode-home/ instead of just the current one.
  --no-usage          Do not auto-print the post-run usage summary
                      (same as OPENCODE_NO_USAGE=1).
  --version           Print the wrapper version and exit
  --help              Show this help
```

Anything after `--` (or any argument the wrapper does not itself recognize) is forwarded to OpenCode, for example `opencode-sandbox auth login` or `opencode-sandbox run "..."`.

## `--print`

`--print` is a dry-run mode: it prints the generated `docker` command and exits without creating `~/.opencode-home` or any optional workspace directories. If `--pull` is also set, it first prints the rebuild command (`docker build --pull --no-cache` for the default local image, or `docker pull` for an `OPENCODE_IMAGE` override) and still exits without changing anything.

## `--init-structure`

Creates these directories in the workspace root:

```text
tasks/       actionable work items
context/     logs, screenshots, payloads, debugging context
tmp/         temporary working files
outputs/     reports, analyses, drafts
```

## Image selection

By default the wrapper builds and uses a local image, `opencode-sandbox:local`, from the embedded Dockerfile. The build runs automatically on the first launch and takes roughly 3-5 minutes; see `docs/architecture.md` for why it is a local Ubuntu build rather than the upstream image.

Override with an explicit registry image:

```bash
OPENCODE_IMAGE=ghcr.io/anomalyco/opencode:<tag> opencode-sandbox
```

`--pull` then runs `docker pull` against that image instead of rebuilding the local default. `--pull` cannot be combined with `--offline`. With an `OPENCODE_IMAGE` override, the post-run usage summary is skipped and `--usage` may not find `tokscale` (it is only baked into the default image).

## Environment variables

| Variable | Effect |
| --- | --- |
| `OPENCODE_IMAGE` | Use this image instead of building/using the local default; disables usage reporting. |
| `OPENCODE_NO_USAGE` | Set (non-empty) to disable the post-run usage summary; same as `--no-usage`. |

## Token usage tracking

`--usage` reports tokens and cost for the current workspace via [tokscale](https://github.com/junhoyeo/tokscale) (pinned to `tokscale@3.0.0`, baked into the default image), reading OpenCode's per-workspace SQLite store directly. No data leaves the machine; tokscale only reaches the network to refresh model pricing (cached locally for an hour).

```bash
opencode-sandbox --usage            # tokens + cost for the current workspace
opencode-sandbox --usage --all      # aggregate across all workspaces
opencode-sandbox --usage --json     # machine-readable output
opencode-sandbox --usage --today    # extra tokscale flags are forwarded
```

`--usage` defaults to a readable table. Any flag after `--usage` that the wrapper does not itself recognize (for example `--json`, `--today`, `--week`, `--group-by session,model`) is forwarded straight to tokscale. Flags the wrapper reserves for itself (`--usage`, `--offline`, `--pull`, `--print`, `--init-structure`, `--all`, `--no-usage`, `--version`, `--help`/`-h`) are still consumed by the wrapper even after `--usage`; use `--` after `--usage` to force everything that follows through to tokscale unchanged.

After a normal run the wrapper prints a one-line summary of today's usage for the workspace, for example:

```text
[opencode-sandbox] token usage today (this workspace): 1286 in, 296 out, $0.0037 (full report: opencode-sandbox --usage)
```

Opt out with `--no-usage` or `OPENCODE_NO_USAGE=1`.

Notes and limitations:
- Reporting requires the bundled default image; an `OPENCODE_IMAGE` override skips the summary and may lack `tokscale`.
- The post-run summary aggregates today's sessions for the workspace, not strictly the run that just finished; use `--usage` for the full breakdown.
- Cost is computed from token counts using public pricing. OpenCode itself stores cost as `0`, so a network-less environment may show tokens without a cost figure.

## `docker-compose.yml`

The Compose file is a simple reference; the preferred path is the `opencode-sandbox` wrapper, because it uses the current working directory directly as the workspace. To use Compose, place your project under `./workspace` or adjust the volume mount.

Unlike the wrapper, the Compose file mounts the shared `${HOME}/.opencode-home` directory as container `HOME`, without per-workspace isolation: every project run through Compose shares the same auth tokens and session history. Point the volume at a per-project subdirectory if you need the isolation the wrapper provides.

Running Compose writes state directly into `~/.opencode-home/` (not into a per-workspace subdirectory), so a later `opencode-sandbox` run against that same home prints its legacy-layout warning, unless that workspace's own state dir already exists (see `docs/troubleshooting.md`).
