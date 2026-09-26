# Troubleshooting

## `AGENTS.md not found` / `PROJECT.md not found` warnings

On a normal run (not `--usage`), the wrapper checks the workspace root for `AGENTS.md` and `PROJECT.md`. If either is missing it prints an informational line such as `[opencode-sandbox][warn] AGENTS.md not found in workspace root.`. These are harmless reminders for agent-style projects; the wrapper still runs normally against any ordinary directory.

## Usage report fails against the bundled image

A non-zero result from `--usage` against the default local image most often means that image predates v0.2.0 and has no `tokscale`. Rebuild it:

```bash
opencode-sandbox --pull
```

## Legacy `~/.opencode-home/` layout warning

Pre-v0.1.0, all workspaces shared a single `~/.opencode-home/` directory. On first run against a newer version, the wrapper detects that legacy layout (files directly under `~/.opencode-home/`, rather than under a per-workspace slug directory) and prints a one-line warning. It does not touch existing state. Move anything you want to keep into the new per-workspace sub-dir (`~/.opencode-home/<workspace-slug>/`) manually.

## Workspace slug changed after upgrading

Earlier releases keyed state on the workspace basename alone, which let two directories that share a basename collide on the same state dir. The slug now appends a short hash of the absolute path (see [Architecture](architecture.md)). State created by an older version stays under the old basename-only directory (`~/.opencode-home/<basename>/`) and is not migrated automatically: the first run after upgrading starts a fresh state dir. Move anything you want to keep (auth, session history) from the old directory into the new one, then remove the old directory.

## Resetting local state

To reset local OpenCode state for a single workspace, remove `~/.opencode-home/<that-slug>/`. To reset everything, remove `~/.opencode-home/` entirely.
