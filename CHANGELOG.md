# Changelog

All notable changes to this project should be documented in this file.

## Unreleased

### Fixed
- The wrapper's workspace-slug hashing now falls back to `shasum -a 256` when `sha256sum` is absent from PATH (stock older macOS ships only `shasum`), so the coreutils `sha256sum` requirement documented in 0.2.2 is dropped. A host with neither tool now gets a clear `[opencode-sandbox][error] Neither sha256sum nor shasum found in PATH.` instead of an unrelated failure.

### Tests
- Closed the four coverage gaps from the 2026-06-27 audit in `tests/smoke.sh`: the docker-not-installed guard, `install.sh`'s `detect_shell_rc` zsh branch and PATH-already-present branch, `install.sh`'s unknown-option / `--help` / missing-source error paths, and the `print_usage_after_run` JSON parsing (compact vs pretty extraction, the `-0.0` sign strip, and the empty-output fallback). Each is mutation-checked. No production behavior change.
- `tests/smoke.sh` itself now works without `sha256sum` on PATH (own slug helper and docker-guard fixture support the `shasum` fallback), and fails fast with a clear message if neither tool is present, instead of a misleading assertion later.

## [0.2.2] - 2026-06-09

Security patch remediating two MEDIUM audit findings.

### Security
- **Per-workspace state slug now disambiguates by absolute path** (#49). The slug was the workspace basename alone, so two directories that share a basename (for example `~/work/api` and `~/play/api`) collided on the same `~/.opencode-home/<slug>/` state dir and shared auth tokens and session history. The slug now appends a short hash of the absolute workspace path, and the container `--name` reuses the same slug. **Upgrader note**: state is re-keyed, so your first run after upgrading starts a fresh state dir under the new slug. State created by an older version stays under the old basename-only directory (`~/.opencode-home/<basename>/`) and is not migrated automatically; move auth and session history over manually if you want to keep it, then remove the old directory.
- **Release workflow hardened against GitHub Actions expression injection** (#48). The git tag version is now passed into `awk` through an env var (`-v`) instead of being interpolated into the `run:` script, closing an expression-injection vector on tag push.

## [0.2.1] - 2026-06-01

### Fixed
- `opencode-sandbox --usage --all` crashed with `settings_dir: unbound variable` under `set -u`: the cleanup `trap ... EXIT` referenced a function-local variable that no longer existed when the trap fired after the function returned. `settings_dir` is now a script-global, read defensively in the trap.
- A usage run against a pre-0.2.0 local image (which has no `tokscale`) printed a bare `exec: tokscale: not found`. It now forwards the exit code and points at the fix: rebuild with `opencode-sandbox --pull`.

## [0.2.0] - 2026-06-01

### Added
- Token-usage tracking. `opencode-sandbox --usage` reports tokens and cost for the current workspace, `--usage --all` aggregates across every workspace under `~/.opencode-home/`, and any extra flags (`--json`, `--today`, ...) pass through to the underlying reporter. After a normal run the wrapper also prints a one-line summary of today's usage for the workspace; opt out with `--no-usage` or `OPENCODE_NO_USAGE=1`.
- Reporting is powered by [tokscale](https://github.com/junhoyeo/tokscale), pinned and baked into the default image (it reads OpenCode's per-workspace SQLite store). The image now also includes bun as the JS runtime tokscale needs.

### Changed
- When auto-usage is active the wrapper no longer `exec`s docker for a normal run: it waits for the container, prints the summary, then exits with the container's exit code. The fast `exec` path is kept when auto-usage is disabled. Usage reporting requires the bundled default image; it is skipped for `OPENCODE_IMAGE` overrides.

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
