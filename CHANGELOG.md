# Changelog

All notable changes to this project should be documented in this file.

## Unreleased

## [0.1.1] - 2026-05-18

### Fixed
- TUI no longer hangs with a blank terminal: the wrapper now builds its own glibc-based image instead of pulling the upstream Alpine image. The upstream `ghcr.io/anomalyco/opencode` ships on Alpine (musl) but bundles a glibc-linked OpenTUI render library; dlopen of `ld-linux-x86-64.so.2` fails and the TUI never renders ([anomalyco/opencode#28070](https://github.com/anomalyco/opencode/issues/28070)).

### Changed
- Default image is now `opencode-sandbox:local`, built on first run from an embedded `Dockerfile` (Ubuntu 24.04 + the upstream installer).
- `--pull` rebuilds the local default image (`docker build --pull --no-cache`); against an `OPENCODE_IMAGE` override it still runs `docker pull`.
- `docker-compose.yml` adds a `build:` stanza so `docker compose build` produces the same image.

### Added
- Top-level `Dockerfile` mirroring the embedded heredoc, for users who want to build out-of-band.
- Smoke-test drift guard: standalone `Dockerfile` and the wrapper's embedded heredoc must match (comments stripped). Catches future single-side edits.
- GitHub Actions release workflow that fires on `v*` tag push, runs CI, then publishes a GitHub Release with notes extracted from the matching `CHANGELOG.md` section.
- Issue templates converted to YAML forms (`bug_report.yml`, `feature_request.yml`); LICENSE / CODE_OF_CONDUCT / SECURITY now carry the contact email and the canonical copyright holder.

## [0.1.0] - 2026-04-23

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
- `install.sh --uninstall`: removes the installed binary, leaves state alone
- **Per-workspace state isolation**: state now lives at `~/.opencode-home/<workspace-slug>/`. Previously every workspace shared `~/.opencode-home/`, leaking auth tokens and session state between unrelated projects.
- One-line warning on legacy state layout so upgraders can decide whether to migrate manually.
