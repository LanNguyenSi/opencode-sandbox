# opencode-sandbox

A small Bash wrapper for running [OpenCode](https://opencode.ai) in Docker, with the current directory as the workspace.

This version is intentionally focused on a stable core: the TUI starts reliably, `run` works, OpenCode arguments are passed through, and there are no experimental modes in the default setup.

## Key features

- resolves the workspace root automatically (Git repo root, or the current directory)
- builds and reuses a local Docker image so the TUI works out of the box (see [docs/architecture.md](docs/architecture.md) for why)
- isolates OpenCode state (auth, session history) per workspace under `~/.opencode-home/<slug>/`
- forwards unknown arguments straight to OpenCode (`auth login`, `run "..."`, `/init`, ...)
- reports token usage and cost via `--usage`, and after a normal run
  (default image; opt out with `--no-usage`)
- `--offline` disables networking for the OpenCode container only (usage
  reporting and image builds still use the network, see
  [docs/architecture.md](docs/architecture.md#container-boundaries)); `--print` is a dry run

## Requirements

- Docker
- Bash
- `sha256sum` or `shasum -a 256` (either works)
- Git is optional; without it the wrapper uses the current directory as the workspace

## Quick start

```bash
chmod +x ./install.sh ./opencode-sandbox
./install.sh
opencode-sandbox
```

The installer copies `opencode-sandbox` to `~/.local/bin`. If that directory is not already on `PATH`, either add it yourself or run `./install.sh --add-path` to append it to the detected shell rc file, then reload that file. To uninstall, run `./install.sh --uninstall` (this leaves `~/.opencode-home/` in place).

The first run builds the local image from the embedded Dockerfile, which takes roughly 3-5 minutes.

## Usage

```bash
opencode-sandbox                                   # interactive TUI
opencode-sandbox auth login                        # pass OpenCode arguments through
opencode-sandbox run "Summarize this workspace"
opencode-sandbox --offline -- run "Summarize this workspace"
opencode-sandbox --usage                           # token usage and cost for this workspace
```

Full flag reference (`--pull`, `--print`, `--init-structure`, `--usage`/`--all`/`--no-usage`, `OPENCODE_IMAGE`, environment variables): [docs/configuration.md](./docs/configuration.md).

## Documentation

- [Architecture](./docs/architecture.md): request flow, per-workspace state isolation, container boundaries, why a local Ubuntu image
- [Configuration](./docs/configuration.md): full CLI flag and environment variable reference, image selection, `docker-compose.yml`
- [Troubleshooting](./docs/troubleshooting.md): warning messages, usage-report failures, state layout upgrades
- [Changelog](./CHANGELOG.md), [Contributing](./CONTRIBUTING.md), [Code of Conduct](./CODE_OF_CONDUCT.md), [Security Policy](./SECURITY.md)

## Development and contributing

```bash
make test    # run tests/smoke.sh
make check   # smoke tests plus docker compose config validation
```

See [CONTRIBUTING.md](./CONTRIBUTING.md) for scope and pull request guidelines.

## License

MIT, see [LICENSE](./LICENSE). This release intentionally keeps a stable core and leaves extended modes (extra hardening, a web launcher) out until they are fully verified.
