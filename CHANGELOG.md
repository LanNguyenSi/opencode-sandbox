# Changelog

All notable changes to this project should be documented in this file.

## Unreleased

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
