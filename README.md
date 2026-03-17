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
source ~/.bashrc
```

If you do not use Bash, reload the shell file reported by `install.sh`.

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
```

## Wrapper behavior

- mounts the current project at `/workspace`
- stores OpenCode state in `~/.opencode-home` on the host
- mounts that directory as the container `HOME`
- passes unknown arguments directly to OpenCode
- automatically uses the Git repository root when applicable
- updates the image only when `--pull` is requested
- supports overriding the image with `OPENCODE_IMAGE=...`

## Important note about `.opencode-home`

This wrapper stores OpenCode state in your user home at `~/.opencode-home`.

That keeps the project workspace clean and avoids creating `.opencode-home` inside each repository.

If you want to reset local OpenCode state, remove or back up `~/.opencode-home`.

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

By default, the wrapper uses `ghcr.io/anomalyco/opencode:latest`.

If you want a pinned or custom image, override it explicitly:

```bash
OPENCODE_IMAGE=ghcr.io/anomalyco/opencode:<tag> opencode-sandbox
```

If you want to refresh the configured image before launching OpenCode, use:

```bash
opencode-sandbox --pull
```

`--pull` pulls exactly the image selected by `OPENCODE_IMAGE` or the default image. It cannot be combined with `--offline`.

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
