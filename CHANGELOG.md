# Changelog

All notable changes to this project should be documented in this file.

## Unreleased

### Changed
- Default image is now `opencode-sandbox:local`, built on first run from an embedded `Dockerfile` (Ubuntu 24.04 + the upstream installer). Previously the wrapper used `ghcr.io/anomalyco/opencode:latest`, which ships on Alpine (musl) and fails to load the glibc-linked OpenTUI render library, leaving the TUI blank ([anomalyco/opencode#28070](https://github.com/anomalyco/opencode/issues/28070)).
- `--pull` rebuilds the local default image (`docker build --pull --no-cache`); against an `OPENCODE_IMAGE` override it still runs `docker pull`.

### Added
- Top-level `Dockerfile` mirroring the embedded build, for users who want to build out-of-band.

## [0.1.0] — 2026-04-23

### Added
- Initial open source project setup
- MIT licensing
- Community health files
- GitHub issue and pull request templates
- Local smoke tests
- CI workflow (syntax check + smoke tests + docker compose validate)
- **shellcheck** step in CI for all shipped shell scripts
- Makefile and editor configuration
- `--version` flag on the wrapper
- `install.sh --uninstall` — removes the installed binary, leaves state alone
- **Per-workspace state isolation** — state now lives at `~/.opencode-home/<workspace-slug>/`. Previously every workspace shared `~/.opencode-home/`, leaking auth tokens and session state between unrelated projects.
- One-line warning on legacy state layout so upgraders can decide whether to migrate manually.
