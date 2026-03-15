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
- `docker-compose.yml`: reference Compose setup
- `README.md`: usage and project overview

## Change guidelines

Preferred changes:

- bug fixes
- shell safety improvements
- reproducibility improvements
- documentation updates

Changes should avoid introducing surprising side effects or unstable defaults.
