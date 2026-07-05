#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

TEST_WORKDIR="$TEST_TMP/workspace"
FAKE_BIN="$TEST_TMP/fake-bin"
TEST_HOME="$TEST_TMP/home"
DOCKER_LOG="$TEST_TMP/docker.log"

mkdir -p "$TEST_WORKDIR" "$FAKE_BIN" "$TEST_HOME"
cp "$ROOT_DIR/opencode-sandbox" "$TEST_WORKDIR/opencode-sandbox"
cp "$ROOT_DIR/PROJECT.md" "$TEST_WORKDIR/PROJECT.md"

cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
{
  printf '%s\n' '---'
  for arg in "$@"; do
    printf '[%s]\n' "$arg"
  done
} >> "$DOCKER_LOG"
# Report the local default image as absent so the wrapper's auto-build path
# runs. Without this, every test would skip build and the behavior would never
# be exercised end-to-end.
if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
  exit 1
fi
# FAKE_DOCKER_RUN_RC lets a test simulate a failing opencode container. It only
# applies to the main run; the tokscale usage run (identified by its writable
# XDG cache env) must still succeed so the post-run summary path is exercised.
if [[ "${1:-}" == "run" ]]; then
  is_tokscale=false
  for arg in "$@"; do
    if [[ "$arg" == "XDG_CACHE_HOME=/tmp/tscache" ]]; then
      is_tokscale=true
      break
    fi
  done
  # FAKE_DOCKER_USAGE_RC fails only the tokscale usage run (simulates a stale
  # image without tokscale); FAKE_DOCKER_RUN_RC fails only the main opencode run.
  if [[ "$is_tokscale" == true && -n "${FAKE_DOCKER_USAGE_RC:-}" ]]; then
    exit "$FAKE_DOCKER_USAGE_RC"
  fi
  if [[ "$is_tokscale" != true && -n "${FAKE_DOCKER_RUN_RC:-}" ]]; then
    exit "$FAKE_DOCKER_RUN_RC"
  fi
  # FAKE_TOKSCALE_JSON, when set, is emitted on stdout for the tokscale usage
  # run so a test can assert the wrapper's JSON parsing and summary output.
  if [[ "$is_tokscale" == true && -n "${FAKE_TOKSCALE_JSON:-}" ]]; then
    printf '%s' "$FAKE_TOKSCALE_JSON"
  fi
fi
exit 0
EOF
chmod +x "$FAKE_BIN/docker" "$TEST_WORKDIR/opencode-sandbox"

run_wrapper() {
  (
    cd "$TEST_WORKDIR"
    HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" bash ./opencode-sandbox "$@"
  )
}

assert_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"

  if [[ "$haystack" == *"$needle"* ]]; then
    printf 'Expected output not to contain: %s\n' "$needle" >&2
    printf 'Actual output:\n%s\n' "$haystack" >&2
    exit 1
  fi
}

assert_not_exists() {
  local path="$1"

  if [[ -e "$path" ]]; then
    printf 'Expected path to be absent: %s\n' "$path" >&2
    exit 1
  fi
}

assert_exists() {
  local path="$1"

  if [[ ! -e "$path" ]]; then
    printf 'Expected path to exist: %s\n' "$path" >&2
    exit 1
  fi
}

# Mirror the wrapper's per-workspace slug scheme: a human-readable basename plus
# a short hash of the absolute path. Two directories that share a basename get
# distinct slugs, so tests must derive the expected slug from the actual workdir
# rather than hard-coding the basename.
workspace_slug() {
  local workdir="$1" name
  name="$(basename "$workdir" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_.-' '-')"
  name="${name#-}"
  name="${name%-}"
  [[ -z "$name" ]] && name="workspace"
  printf '%s-%s' "$name" "$(printf '%s' "$workdir" | sha256sum | cut -c1-8)"
}

TEST_SLUG="$(workspace_slug "$TEST_WORKDIR")"

# Regression: two workspaces that share a basename must NOT share a slug, or
# their auth/session state would collide (audit finding #49).
collision_a="$TEST_TMP/dir-a/project"
collision_b="$TEST_TMP/dir-b/project"
mkdir -p "$collision_a" "$collision_b"
if [[ "$(workspace_slug "$collision_a")" == "$(workspace_slug "$collision_b")" ]]; then
  printf 'Slug collision: same-basename workspaces produced identical slugs\n' >&2
  exit 1
fi

print_output="$(run_wrapper --print 2>&1)"
assert_contains "$print_output" "docker run --rm -i --name opencode-$TEST_SLUG"
assert_contains "$print_output" "opencode-sandbox:local"
# Per-workspace home: the disambiguated slug (basename + path hash) is appended.
assert_contains "$print_output" "-v $TEST_HOME/.opencode-home/$TEST_SLUG:/opencode-home"
assert_contains "$print_output" "-e HOME=/opencode-home"
assert_contains "$print_output" "[opencode-sandbox][warn] No Git repository detected."
assert_contains "$print_output" "[opencode-sandbox][warn] AGENTS.md not found in workspace root."
assert_not_contains "$print_output" " -t "

# --version prints the version string and exits without invoking docker.
: > "$DOCKER_LOG"
version_output="$(run_wrapper --version 2>&1)"
assert_contains "$version_output" "opencode-sandbox 0.2.2"
if [[ -s "$DOCKER_LOG" ]]; then
  printf 'Expected --version not to invoke docker, but docker was called:\n%s\n' \
    "$(cat "$DOCKER_LOG")" >&2
  exit 1
fi

# Legacy-layout detection: a pre-v0.1.0 shared ~/.opencode-home/ with files
# directly inside triggers a one-line warn. The new run still works.
legacy_home="$TEST_TMP/legacy-home"
mkdir -p "$legacy_home/.opencode-home"
echo "fake-auth" > "$legacy_home/.opencode-home/auth.json"
legacy_output="$(
  cd "$TEST_WORKDIR"
  HOME="$legacy_home" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox --print 2>&1
)"
assert_contains "$legacy_output" "Legacy ~/.opencode-home/ state detected"
assert_contains "$legacy_output" "$legacy_home/.opencode-home/$TEST_SLUG:/opencode-home"

# Same workspace with the new per-slug sub-dir already present, so no legacy warn.
clean_home="$TEST_TMP/clean-home"
mkdir -p "$clean_home/.opencode-home/$TEST_SLUG"
clean_output="$(
  cd "$TEST_WORKDIR"
  HOME="$clean_home" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox --print 2>&1
)"
assert_not_contains "$clean_output" "Legacy ~/.opencode-home/ state detected"

init_print_output="$(run_wrapper --init-structure --print 2>&1)"
assert_contains "$init_print_output" "docker run --rm -i --name opencode-$TEST_SLUG"
assert_not_exists "$TEST_WORKDIR/.opencode-home"
assert_not_exists "$TEST_HOME/.opencode-home"
assert_not_exists "$TEST_WORKDIR/tasks"
assert_not_exists "$TEST_WORKDIR/context"
assert_not_exists "$TEST_WORKDIR/tmp"
assert_not_exists "$TEST_WORKDIR/outputs"

offline_output="$(run_wrapper --offline --print 2>&1)"
assert_contains "$offline_output" "--network none"

pull_print_output="$(run_wrapper --pull --print 2>&1)"
assert_contains "$pull_print_output" "docker build --pull --no-cache -t opencode-sandbox:local"
assert_contains "$pull_print_output" "docker run --rm -i --name opencode-$TEST_SLUG"

# OPENCODE_IMAGE override switches --pull --print back to docker pull.
pull_print_override_output="$(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" OPENCODE_IMAGE="example.invalid/opencode:test" bash ./opencode-sandbox --pull --print 2>&1
)"
assert_contains "$pull_print_override_output" "docker pull example.invalid/opencode:test"
assert_not_contains "$pull_print_override_output" "docker build"

pull_offline_stdout="$TEST_TMP/pull-offline.stdout"
pull_offline_stderr="$TEST_TMP/pull-offline.stderr"
if run_wrapper --pull --offline >"$pull_offline_stdout" 2>"$pull_offline_stderr"; then
  printf 'Expected --pull --offline to fail\n' >&2
  exit 1
fi
assert_contains "$(cat "$pull_offline_stderr")" "--pull cannot be combined with --offline."

space_dir="$TEST_TMP/Space Dir"
mkdir -p "$space_dir"
cp "$ROOT_DIR/opencode-sandbox" "$space_dir/opencode-sandbox"
cat > "$space_dir/PROJECT.md" <<'EOF'
# Test Project
EOF
chmod +x "$space_dir/opencode-sandbox"

space_output="$(
  cd "$space_dir"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox --print 2>&1
)"
assert_contains "$space_output" "--name opencode-$(workspace_slug "$space_dir")"

if command -v git >/dev/null 2>&1; then
  git_root="$TEST_TMP/git-root"
  git_nested="$git_root/nested/deeper"
  mkdir -p "$git_nested"
  (
    cd "$git_root"
    git init -q
  )
  cp "$ROOT_DIR/opencode-sandbox" "$git_nested/opencode-sandbox"
  cp "$ROOT_DIR/PROJECT.md" "$git_root/PROJECT.md"
  touch "$git_root/AGENTS.md"
  chmod +x "$git_nested/opencode-sandbox"

  git_output="$(
    cd "$git_nested"
    HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox --print 2>&1
  )"
  assert_contains "$git_output" "-v $git_root:/workspace"
  assert_contains "$git_output" "--name opencode-$(workspace_slug "$git_root")"
  assert_not_contains "$git_output" "No Git repository detected."
fi

touch "$TEST_WORKDIR/AGENTS.md"
run_wrapper --init-structure >/dev/null 2>&1 || {
  printf 'Expected --init-structure run to succeed\n' >&2
  exit 1
}
assert_exists "$TEST_WORKDIR/tasks"
assert_exists "$TEST_WORKDIR/context"
assert_exists "$TEST_WORKDIR/tmp"
assert_exists "$TEST_WORKDIR/outputs"
assert_exists "$TEST_HOME/.opencode-home"

: > "$DOCKER_LOG"
run_wrapper --pull >/dev/null 2>&1 || {
  printf 'Expected --pull run to succeed\n' >&2
  exit 1
}
docker_log_contents="$(cat "$DOCKER_LOG")"
assert_contains "$docker_log_contents" "[build]"
assert_contains "$docker_log_contents" "[--pull]"
assert_contains "$docker_log_contents" "[--no-cache]"
assert_contains "$docker_log_contents" "[opencode-sandbox:local]"
assert_contains "$docker_log_contents" "[run]"
assert_contains "$docker_log_contents" "[--name]"
assert_contains "$docker_log_contents" "[opencode-$TEST_SLUG]"

# Without --pull, auto-build is triggered when the local image is absent
# (the fake docker reports `image inspect` as nonzero for that exact case).
: > "$DOCKER_LOG"
run_wrapper >/dev/null 2>&1 || {
  printf 'Expected default run to succeed\n' >&2
  exit 1
}
docker_log_contents="$(cat "$DOCKER_LOG")"
assert_contains "$docker_log_contents" "[image]"
assert_contains "$docker_log_contents" "[inspect]"
assert_contains "$docker_log_contents" "[build]"
assert_contains "$docker_log_contents" "[run]"

: > "$DOCKER_LOG"
run_wrapper -- --pull --help "two words" >/dev/null 2>&1 || {
  printf 'Expected passthrough invocation to succeed\n' >&2
  exit 1
}
docker_log_contents="$(cat "$DOCKER_LOG")"
assert_not_contains "$docker_log_contents" "[pull]"
assert_contains "$docker_log_contents" "[run]"
assert_contains "$docker_log_contents" "[--pull]"
assert_contains "$docker_log_contents" "[--help]"
assert_contains "$docker_log_contents" "[two words]"

custom_image_output="$(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" OPENCODE_IMAGE="example.invalid/opencode:test" bash ./opencode-sandbox --print 2>&1
)"
assert_contains "$custom_image_output" "example.invalid/opencode:test"

# --usage --print: dry-run of the tokscale invocation against the per-workspace
# store. Reads the home read-only, defaults to a --light table, does not run
# docker or touch any state.
: > "$DOCKER_LOG"
usage_print_output="$(run_wrapper --usage --print 2>&1)"
assert_contains "$usage_print_output" "-v $TEST_HOME/.opencode-home/$TEST_SLUG:/data:ro"
assert_contains "$usage_print_output" "tokscale"
assert_contains "$usage_print_output" "--home /data"
assert_contains "$usage_print_output" "--client opencode"
assert_contains "$usage_print_output" "--no-spinner"
assert_contains "$usage_print_output" "--light"
if [[ -s "$DOCKER_LOG" ]]; then
  printf 'Expected --usage --print not to invoke docker, but it did:\n%s\n' "$(cat "$DOCKER_LOG")" >&2
  exit 1
fi

# An explicit --json suppresses the default --light table and is forwarded.
usage_json_output="$(run_wrapper --usage --json --print 2>&1)"
assert_contains "$usage_json_output" "--json"
assert_not_contains "$usage_json_output" "--light"

# --usage --all mounts the home root read-only and feeds tokscale a generated
# settings file listing every workspace DB.
usage_all_output="$(run_wrapper --usage --all --print 2>&1)"
assert_contains "$usage_all_output" "-v $TEST_HOME/.opencode-home:/data:ro"
assert_contains "$usage_all_output" "settings.json"
assert_not_contains "$usage_all_output" "--home /data"

# Regression: `--usage --all` (real, non-print) generates a temp settings dir
# and registers an EXIT trap to clean it. The trap must read a script-global
# settings_dir, not a function-local one, or it trips `set -u` with
# "settings_dir: unbound variable" at exit. Needs a discoverable DB.
usage_all_db="$TEST_HOME/.opencode-home/$TEST_SLUG/.local/share/opencode"
mkdir -p "$usage_all_db"
: > "$usage_all_db/opencode.db"
: > "$DOCKER_LOG"
set +e
usage_all_run_out="$(run_wrapper --usage --all 2>&1)"
usage_all_rc=$?
set -e
if [[ "$usage_all_rc" -ne 0 ]]; then
  printf 'Expected --usage --all to exit 0, got %s:\n%s\n' "$usage_all_rc" "$usage_all_run_out" >&2
  exit 1
fi
assert_not_contains "$usage_all_run_out" "unbound variable"
assert_contains "$(cat "$DOCKER_LOG")" "XDG_CACHE_HOME=/tmp/tscache"

# Regression: a usage run that fails against the bundled image (e.g. a pre-v0.2.0
# image with no tokscale) must forward the exit code and emit the --pull hint
# rather than a bare "tokscale: not found".
: > "$DOCKER_LOG"
set +e
stale_hint_out="$(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" FAKE_DOCKER_USAGE_RC=127 bash ./opencode-sandbox --usage 2>&1
)"
stale_rc=$?
set -e
if [[ "$stale_rc" -ne 127 ]]; then
  printf 'Expected failing usage run to forward exit 127, got %s\n' "$stale_rc" >&2
  exit 1
fi
assert_contains "$stale_hint_out" "opencode-sandbox --pull"

# Auto-print after a normal run: with a workspace DB present, the wrapper runs
# tokscale once more (today's usage) after the container exits.
usage_db_dir="$TEST_HOME/.opencode-home/$TEST_SLUG/.local/share/opencode"
mkdir -p "$usage_db_dir"
: > "$usage_db_dir/opencode.db"
: > "$DOCKER_LOG"
run_wrapper >/dev/null 2>&1 || {
  printf 'Expected default run with auto-usage to succeed\n' >&2
  exit 1
}
auto_usage_log="$(cat "$DOCKER_LOG")"
# The tokscale invocation is uniquely identified by its writable XDG cache env;
# the normal opencode run never sets it. tokscale's own flags live inside the
# `sh -c` script, so they are logged as one argument, not separate brackets.
assert_contains "$auto_usage_log" "XDG_CACHE_HOME=/tmp/tscache"
assert_contains "$auto_usage_log" "--today"

# A failing opencode container must still forward its exit code AND still run
# the post-run summary (the wrapper captures the code inline rather than letting
# `set -e` abort before the summary).
: > "$DOCKER_LOG"
set +e
(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" FAKE_DOCKER_RUN_RC=7 bash ./opencode-sandbox >/dev/null 2>&1
)
fail_rc=$?
set -e
if [[ "$fail_rc" -ne 7 ]]; then
  printf 'Expected failing run to forward exit code 7, got %s\n' "$fail_rc" >&2
  exit 1
fi
assert_contains "$(cat "$DOCKER_LOG")" "XDG_CACHE_HOME=/tmp/tscache"

# --no-usage opts out of the post-run summary.
: > "$DOCKER_LOG"
run_wrapper --no-usage >/dev/null 2>&1 || {
  printf 'Expected --no-usage run to succeed\n' >&2
  exit 1
}
assert_not_contains "$(cat "$DOCKER_LOG")" "XDG_CACHE_HOME=/tmp/tscache"

# OPENCODE_NO_USAGE=1 also opts out.
: > "$DOCKER_LOG"
(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" OPENCODE_NO_USAGE=1 bash ./opencode-sandbox >/dev/null 2>&1
) || {
  printf 'Expected OPENCODE_NO_USAGE run to succeed\n' >&2
  exit 1
}
assert_not_contains "$(cat "$DOCKER_LOG")" "XDG_CACHE_HOME=/tmp/tscache"

# A custom OPENCODE_IMAGE has no bundled tokscale, so auto-print is skipped.
: > "$DOCKER_LOG"
(
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" OPENCODE_IMAGE="example.invalid/opencode:test" bash ./opencode-sandbox >/dev/null 2>&1
) || {
  printf 'Expected custom-image run to succeed\n' >&2
  exit 1
}
assert_not_contains "$(cat "$DOCKER_LOG")" "XDG_CACHE_HOME=/tmp/tscache"

# docker-not-installed guard (opencode-sandbox:286). run_wrapper always prepends
# a fake `docker` to PATH, so the hard-fail path is otherwise never exercised.
# Build a PATH that carries the coreutils the wrapper needs before the check
# (basename, tr, sha256sum, cut) but no docker, and assert the guard aborts with
# the right message and a non-zero exit. Invoke bash by absolute path so finding
# the interpreter itself does not depend on the stripped PATH.
NODOCKER_BIN="$TEST_TMP/nodocker-bin"
mkdir -p "$NODOCKER_BIN"
for tool in basename tr sha256sum cut find grep dirname; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  if [[ -n "$tool_path" ]]; then
    ln -sf "$tool_path" "$NODOCKER_BIN/$tool"
  fi
done
BASH_BIN="$(command -v bash)"
nodocker_stderr="$TEST_TMP/nodocker.stderr"
if (
  cd "$TEST_WORKDIR"
  HOME="$TEST_TMP/nodocker-home" PATH="$NODOCKER_BIN" "$BASH_BIN" ./opencode-sandbox
) >/dev/null 2>"$nodocker_stderr"; then
  printf 'Expected the wrapper to fail when docker is absent\n' >&2
  exit 1
fi
assert_contains "$(cat "$nodocker_stderr")" "[opencode-sandbox][error] Docker is not installed or not available in PATH."

# print_usage_after_run JSON parsing (opencode-sandbox:209-215). The fake docker
# emits FAKE_TOKSCALE_JSON on the tokscale usage run so we can assert the summary
# line shows each total extracted DISTINCTLY (the anchored grep must not collapse
# them) from compact JSON, and that a -0.0 cost has its sign stripped from pretty
# JSON.
usage_compact_stderr="$TEST_TMP/usage-compact.stderr"
if ! (
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" \
    FAKE_TOKSCALE_JSON='{"totalInput":1234,"totalOutput":5678,"totalCost":9.5}' \
    "$BASH_BIN" ./opencode-sandbox
) >/dev/null 2>"$usage_compact_stderr"; then
  printf 'Expected the wrapper run to succeed for the usage-parse test\n' >&2
  exit 1
fi
assert_contains "$(cat "$usage_compact_stderr")" "token usage today (this workspace): 1234 in, 5678 out, \$9.5 "

usage_pretty_stderr="$TEST_TMP/usage-pretty.stderr"
if ! (
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" \
    FAKE_TOKSCALE_JSON='{
  "totalInput": 0,
  "totalOutput": 42,
  "totalCost": -0.0
}' \
    "$BASH_BIN" ./opencode-sandbox
) >/dev/null 2>"$usage_pretty_stderr"; then
  printf 'Expected the wrapper run to succeed for the pretty-JSON usage-parse test\n' >&2
  exit 1
fi
assert_contains "$(cat "$usage_pretty_stderr")" "token usage today (this workspace): 0 in, 42 out, \$0.0 "

# Empty tokscale output falls back to the ${tin:-0}/${tout:-0}/${tcost:-0}
# defaults (opencode-sandbox:216) instead of printing blank fields.
usage_empty_stderr="$TEST_TMP/usage-empty.stderr"
if ! (
  cd "$TEST_WORKDIR"
  HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" DOCKER_LOG="$DOCKER_LOG" \
    FAKE_TOKSCALE_JSON='' \
    "$BASH_BIN" ./opencode-sandbox
) >/dev/null 2>"$usage_empty_stderr"; then
  printf 'Expected the wrapper run to succeed for the empty-JSON usage test\n' >&2
  exit 1
fi
assert_contains "$(cat "$usage_empty_stderr")" "token usage today (this workspace): 0 in, 0 out, \$0 "

rm -rf "$TEST_HOME/.opencode-home/$TEST_SLUG/.local"

INSTALL_TEST_HOME="$TEST_TMP/install-home"
INSTALL_TEST_DIR="$TEST_TMP/install-src"
mkdir -p "$INSTALL_TEST_HOME" "$INSTALL_TEST_DIR"
cp "$ROOT_DIR/install.sh" "$INSTALL_TEST_DIR/install.sh"
cp "$ROOT_DIR/opencode-sandbox" "$INSTALL_TEST_DIR/opencode-sandbox"
chmod +x "$INSTALL_TEST_DIR/install.sh" "$INSTALL_TEST_DIR/opencode-sandbox"

install_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh 2>&1
)"
assert_contains "$install_output" "Installed: $INSTALL_TEST_HOME/.local/bin/opencode-sandbox"
assert_contains "$install_output" "PATH does not contain ~/.local/bin"
assert_contains "$install_output" "./install.sh --add-path"
assert_not_exists "$INSTALL_TEST_HOME/.bashrc"
assert_exists "$INSTALL_TEST_HOME/.local/bin/opencode-sandbox"

: > "$INSTALL_TEST_HOME/.bashrc"
install_add_path_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --add-path 2>&1
)"
assert_contains "$install_add_path_output" "Added PATH entry to $INSTALL_TEST_HOME/.bashrc"
# shellcheck disable=SC2016  # literal; the rc file expands $HOME at shell startup
assert_contains "$(cat "$INSTALL_TEST_HOME/.bashrc")" 'export PATH="$HOME/.local/bin:$PATH"'

# --uninstall removes the installed binary, leaves state alone.
assert_exists "$INSTALL_TEST_HOME/.local/bin/opencode-sandbox"
mkdir -p "$INSTALL_TEST_HOME/.opencode-home/some-workspace"
echo "preserved" > "$INSTALL_TEST_HOME/.opencode-home/some-workspace/marker"
uninstall_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --uninstall 2>&1
)"
assert_contains "$uninstall_output" "Removed: $INSTALL_TEST_HOME/.local/bin/opencode-sandbox"
assert_contains "$uninstall_output" "State dir $INSTALL_TEST_HOME/.opencode-home left in place"
assert_not_exists "$INSTALL_TEST_HOME/.local/bin/opencode-sandbox"
assert_exists "$INSTALL_TEST_HOME/.opencode-home/some-workspace/marker"

# --uninstall is idempotent — re-running is a no-op with a friendly message.
uninstall_again="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --uninstall 2>&1
)"
assert_contains "$uninstall_again" "Nothing to remove at: $INSTALL_TEST_HOME/.local/bin/opencode-sandbox"

# --uninstall rejects --add-path combination.
combined_stderr="$TEST_TMP/uninstall-combined.stderr"
if (
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --uninstall --add-path
) >/dev/null 2>"$combined_stderr"; then
  printf 'Expected --uninstall --add-path to fail\n' >&2
  exit 1
fi
assert_contains "$(cat "$combined_stderr")" "--uninstall cannot be combined with --add-path"

# detect_shell_rc zsh branch (install.sh:26-27): a zsh user whose ~/.local/bin is
# not yet on PATH must get their ~/.zshrc wired, not ~/.bashrc.
ZSH_TEST_HOME="$TEST_TMP/install-home-zsh"
mkdir -p "$ZSH_TEST_HOME"
zsh_install_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$ZSH_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/usr/bin/zsh" bash ./install.sh --add-path 2>&1
)"
assert_contains "$zsh_install_output" "Added PATH entry to $ZSH_TEST_HOME/.zshrc"
# shellcheck disable=SC2016  # literal; the rc file expands $HOME at shell startup
assert_contains "$(cat "$ZSH_TEST_HOME/.zshrc")" 'export PATH="$HOME/.local/bin:$PATH"'
assert_not_exists "$ZSH_TEST_HOME/.bashrc"

# PATH-already-present branch (install.sh:104): when ~/.local/bin is already on
# PATH, the installer says so and does not print the "does not contain" guidance.
ALREADY_TEST_HOME="$TEST_TMP/install-home-already"
mkdir -p "$ALREADY_TEST_HOME"
already_install_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$ALREADY_TEST_HOME" PATH="$ALREADY_TEST_HOME/.local/bin:/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh 2>&1
)"
assert_contains "$already_install_output" "PATH already contains ~/.local/bin"
assert_not_contains "$already_install_output" "PATH does not contain"

# Unknown-option rejection (install.sh:63): an unrecognized flag aborts non-zero
# with a named error.
unknown_opt_stderr="$TEST_TMP/install-unknown.stderr"
if (
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --bogus-flag
) >/dev/null 2>"$unknown_opt_stderr"; then
  printf 'Expected install.sh to reject an unknown option\n' >&2
  exit 1
fi
assert_contains "$(cat "$unknown_opt_stderr")" "Error: unknown option '--bogus-flag'"

# --help / -h (install.sh:58): prints usage and exits 0 without installing.
help_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh --help 2>&1
)"
assert_contains "$help_output" "Usage: install.sh"
help_short_output="$(
  cd "$INSTALL_TEST_DIR"
  HOME="$INSTALL_TEST_HOME" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh -h 2>&1
)"
assert_contains "$help_short_output" "Usage: install.sh"

# Missing source-script guard (install.sh:89): install.sh run without its sibling
# opencode-sandbox wrapper aborts non-zero instead of installing an empty target.
NOSRC_DIR="$TEST_TMP/install-nosrc"
mkdir -p "$NOSRC_DIR"
cp "$ROOT_DIR/install.sh" "$NOSRC_DIR/install.sh"
chmod +x "$NOSRC_DIR/install.sh"
nosrc_out="$TEST_TMP/install-nosrc.out"
if (
  cd "$NOSRC_DIR"
  HOME="$TEST_TMP/install-home-nosrc" PATH="/usr/bin:/bin" SHELL="/bin/bash" bash ./install.sh
) >"$nosrc_out" 2>&1; then
  printf 'Expected install.sh to fail when the source wrapper is missing\n' >&2
  exit 1
fi
assert_contains "$(cat "$nosrc_out")" "was not found"
assert_not_exists "$TEST_TMP/install-home-nosrc/.local/bin/opencode-sandbox"

# The Dockerfile lives in two places: as a standalone file (used by
# docker-compose's build:) and embedded as a heredoc in the wrapper (so the
# installed script is self-contained). They will silently drift if a future
# change touches only one. Compare the meaningful lines.
extracted_embedded="$TEST_TMP/embedded.Dockerfile"
sed -n "/<<'DOCKERFILE'$/,/^DOCKERFILE$/p" "$ROOT_DIR/opencode-sandbox" \
  | sed '1d;$d' > "$extracted_embedded"
ondisk_no_comments="$TEST_TMP/ondisk-stripped.Dockerfile"
grep -vE '^[[:space:]]*(#|$)' "$ROOT_DIR/Dockerfile" > "$ondisk_no_comments"
embedded_no_comments="$TEST_TMP/embedded-stripped.Dockerfile"
grep -vE '^[[:space:]]*(#|$)' "$extracted_embedded" > "$embedded_no_comments"
if ! diff -u "$ondisk_no_comments" "$embedded_no_comments" >/dev/null; then
  printf 'Dockerfile drift: standalone Dockerfile and the heredoc embedded in opencode-sandbox differ.\n' >&2
  diff -u "$ondisk_no_comments" "$embedded_no_comments" >&2 || true
  exit 1
fi

printf 'smoke tests: ok\n'
