# opencode-sandbox

A small wrapper for running OpenCode in Docker with the current directory as the workspace.

This version is intentionally focused on a stable core:
- the TUI starts reliably
- `run` works
- OpenCode arguments are passed through
- no experimental modes in the default setup

## Included

- `opencode-sandbox`: wrapper script
- `install.sh`: installs `opencode-sandbox` to `~/.local/bin`
- `docker-compose.yml`: simple reference configuration

## Requirements

- Docker
- Bash
- optional Git

Git is not required. If the current directory is not a Git repository, the wrapper simply uses the current directory as the workspace.

## Installation

```bash
chmod +x ./install.sh ./opencode-sandbox
./install.sh
```

The installer copies `opencode-sandbox` to `~/.local/bin` and does not edit shell startup files unless you ask it to.

If `~/.local/bin` is not already in `PATH`, either add it yourself or let the installer update the detected shell file:

```bash
./install.sh --add-path
```

Then reload the shell file reported by `install.sh`.

### Uninstall

```bash
./install.sh --uninstall
```

Removes the wrapper from `~/.local/bin`. Your `~/.opencode-home/` state (auth, session history) is left in place — remove it manually if you no longer need it.

## Quick checks

```bash
make test
make check
```

## Usage

### Interactive TUI

```bash
opencode-sandbox
```

### Pass OpenCode arguments through

```bash
opencode-sandbox auth login
opencode-sandbox run "Give me a one sentence summary of this workspace"
opencode-sandbox /init
```

### Wrapper options

```bash
opencode-sandbox --print
opencode-sandbox --pull
opencode-sandbox --offline -- run "Summarize this workspace"
opencode-sandbox --init-structure
opencode-sandbox --usage
opencode-sandbox --usage --all
opencode-sandbox --version
```

## Wrapper behavior

- mounts the current project at `/workspace`
- stores OpenCode state in `~/.opencode-home/<workspace-slug>/` on the host, isolated per workspace so auth tokens and session history don't leak between unrelated projects
- mounts that directory as the container `HOME`
- passes unknown arguments directly to OpenCode
- automatically uses the Git repository root when applicable
- builds a local `opencode-sandbox:local` image from an embedded Dockerfile on first run, rebuilds it when `--pull` is requested
- supports overriding the image with `OPENCODE_IMAGE=...` (a registry image; in that case `--pull` runs `docker pull` instead of rebuilding)

## Token usage tracking

The wrapper can report how many tokens (and how much money) your OpenCode
sessions consumed. Reporting is handled by
[tokscale](https://github.com/junhoyeo/tokscale), which is baked into the
default image and reads OpenCode's per-workspace SQLite store directly. No data
leaves your machine; tokscale only reaches the network to refresh model pricing
(cached locally for an hour).

```bash
opencode-sandbox --usage            # tokens + cost for the current workspace
opencode-sandbox --usage --all      # aggregate across all workspaces
opencode-sandbox --usage --json     # machine-readable output
opencode-sandbox --usage --today    # any extra flag is forwarded to tokscale
```

`--usage` defaults to a readable table. Any flag you pass after `--usage` (for
example `--json`, `--today`, `--week`, `--group-by session,model`) is forwarded
straight to tokscale.

After a normal run the wrapper prints a one-line summary of today's usage for
the workspace, for example:

```text
[opencode-sandbox] token usage today (this workspace): 1286 in, 296 out, $0.0037 (full report: opencode-sandbox --usage)
```

Opt out of the post-run line with `--no-usage` or `OPENCODE_NO_USAGE=1`.

Notes and limitations:
- Reporting requires the bundled default image. With an `OPENCODE_IMAGE`
  override the post-run summary is skipped and `--usage` may not find tokscale.
- The post-run summary aggregates today's sessions for the workspace, not
  strictly the single run that just finished. Use `--usage` for the full
  breakdown.
- Cost is computed from token counts using public pricing. OpenCode itself
  stores cost as `0`, so a network-less environment may show tokens without a
  cost figure.

## Important note about `.opencode-home`

This wrapper stores OpenCode state in your user home under `~/.opencode-home/<workspace-slug>/`, where `<workspace-slug>` is the workspace directory's basename (the Git repo root's basename, or the current directory's basename when there is no repo) followed by a short hash of its absolute path. Only the basename is human-readable; the full path is not encoded. The path hash keeps two different directories that happen to share a basename (for example `~/work/api` and `~/play/api`) from colliding on the same state dir.

That keeps the project workspace clean, avoids creating `.opencode-home` inside each repository, and — since v0.1.0 — keeps auth tokens and session history scoped to one project.

### Upgrading from pre-v0.1.0

Pre-v0.1.0 all workspaces shared a single `~/.opencode-home/`. On first run against v0.1.0+ the wrapper detects the legacy layout (files directly under `~/.opencode-home/`) and prints a one-line warning. It does **not** touch your existing state. Move anything you want to keep into the new per-workspace sub-dir manually.

### Slug scheme change

Earlier releases keyed state on the workspace basename alone, which let two directories that share a basename collide on the same state dir. The slug now appends a short hash of the absolute path. State created by an older version stays under the old basename-only directory (`~/.opencode-home/<basename>/`) and is **not** migrated automatically: your first run after upgrading starts a fresh state dir. Move anything you want to keep (auth, session history) from the old directory into the new one, then remove the old directory.

If you want to reset local OpenCode state for a single workspace, remove `~/.opencode-home/<that-slug>/`. To reset everything, remove `~/.opencode-home/` entirely.

## Optional project structure

With `--init-structure`, the wrapper creates these directories:

```text
tasks/
context/
tmp/
outputs/
```

Suggested roles:
- `tasks/`: actionable work items
- `context/`: logs, screenshots, payloads, debugging context
- `tmp/`: temporary working files
- `outputs/`: reports, analyses, drafts

## `--print` behavior

`--print` is a real dry-run mode. It prints the generated Docker command and exits without creating `~/.opencode-home` or any optional workspace directories.

If `--pull` is also set, `--print` prints the `docker pull` command first and still exits without changing anything.

## Image selection

By default, the wrapper builds and uses a local image, `opencode-sandbox:local`, from an embedded Dockerfile (Ubuntu 24.04 + the official `opencode.ai/install` script, plus bun and the `tokscale` CLI used for usage reporting). The build runs automatically on the first launch and takes roughly 3-5 minutes.

The local-build default exists because the upstream `ghcr.io/anomalyco/opencode` image is an Alpine (musl) image, while opencode bundles a glibc-linked OpenTUI render library. On those images the TUI fails to initialize with `Error loading shared library ld-linux-x86-64.so.2`, and the process hangs with a blank terminal. See [anomalyco/opencode#28070](https://github.com/anomalyco/opencode/issues/28070).

If you want to use a registry image anyway, override it explicitly:

```bash
OPENCODE_IMAGE=ghcr.io/anomalyco/opencode:<tag> opencode-sandbox
```

To refresh:

```bash
opencode-sandbox --pull
```

`--pull` rebuilds the local default image (`docker build --pull --no-cache`), or runs `docker pull` against an `OPENCODE_IMAGE` override. It cannot be combined with `--offline`.

## docker-compose.yml

The Compose file is intended as a simple reference. The preferred path is currently the `opencode-sandbox` wrapper, because it uses the current working directory directly as the workspace.

If you want to use Compose, place your project under `./workspace` or adjust the volume mount.

## Project docs

- [Contributing](./CONTRIBUTING.md)
- [Code of Conduct](./CODE_OF_CONDUCT.md)
- [Security Policy](./SECURITY.md)
- [Changelog](./CHANGELOG.md)

## Intentionally not included

This release intentionally does not include extended modes such as extra hardening or a web launcher, because they are not fully verified in the current state.

The goal of this version is a clear, working default.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
