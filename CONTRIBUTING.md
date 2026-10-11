# Contributing

Thanks for contributing to `opencode-sandbox`.

## Scope

This project aims to stay small and predictable. Changes are most likely to be accepted when they improve one of these areas:

- wrapper correctness
- Docker runtime safety
- documentation clarity
- reproducibility

Large feature additions should start with an issue or a short design note before implementation.

## Development

Requirements:

- Bash
- Docker

Recommended checks before opening a pull request:

```bash
make test
make check
```

CI also runs `bash -n` and `shellcheck --shell=bash ./opencode-sandbox ./install.sh ./tests/smoke.sh`; run them locally if shellcheck is installed.

The Dockerfile exists twice: the standalone `Dockerfile` and the heredoc in `opencode-sandbox`. Change both; `make test` fails if their non-comment lines differ.

When changing wrapper behavior:

- keep argument parsing simple
- prefer explicit shell-safe quoting
- avoid adding side effects to `--print`
- preserve non-Git workspace support

## Releasing (maintainers)

- bump `VERSION` in `opencode-sandbox` and both version assertions in `tests/smoke.sh`
- add a `## [X.Y.Z]` section to `CHANGELOG.md`; the release notes are taken from it
- push a `vX.Y.Z` tag, which runs CI and creates the GitHub release

## Pull requests

Please keep pull requests focused. A good PR usually includes:

- a short problem statement
- the behavioral change
- any compatibility or migration notes
- README.md or docs/ updates when the user-facing behavior changes

## Reporting issues

When filing a bug, include:

- host OS
- Docker version
- the command you ran
- the generated `--print` output when relevant
- the observed error message
