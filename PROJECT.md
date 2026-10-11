# Project Overview

`opencode-sandbox` is a small Bash wrapper for running OpenCode inside Docker against the current workspace.

## Goals

- keep the runtime model simple
- prefer predictable Docker invocation over feature breadth
- support both Git and non-Git directories
- keep documentation clear and contributor-friendly

## Repository contents

- `opencode-sandbox`: main wrapper script
- `install.sh`: local installer for `~/.local/bin`
- `Dockerfile`: standalone image definition, kept identical to the wrapper's embedded copy
- `docker-compose.yml`: reference Compose setup
- `README.md`: usage and project overview
- `docs/`: architecture, configuration and troubleshooting
- `tests/smoke.sh`: smoke tests
- `Makefile`: test, check and install targets

## Change guidelines

Preferred changes:

- bug fixes
- shell safety improvements
- reproducibility improvements
- documentation updates

Changes should avoid introducing surprising side effects or unstable defaults.
