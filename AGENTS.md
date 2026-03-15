# AGENTS.md

## Project intent

This repository contains a small Bash wrapper around Docker for running OpenCode against the current workspace.

## Expectations for changes

- keep the wrapper simple
- avoid hidden side effects
- preserve shell-safe argument handling
- update `README.md` when user-facing behavior changes
- keep defaults stable and predictable

## Files to review first

- `README.md`
- `PROJECT.md`
- `opencode-sandbox`
- `install.sh`
