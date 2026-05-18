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

print_output="$(run_wrapper --print 2>&1)"
assert_contains "$print_output" "docker run --rm -i --name opencode-workspace"
assert_contains "$print_output" "opencode-sandbox:local"
# Per-workspace home: the basename slug ("workspace" fallback here) is appended.
assert_contains "$print_output" "-v $TEST_HOME/.opencode-home/workspace:/opencode-home"
assert_contains "$print_output" "-e HOME=/opencode-home"
assert_contains "$print_output" "[opencode-sandbox][warn] No Git repository detected."
assert_contains "$print_output" "[opencode-sandbox][warn] AGENTS.md not found in workspace root."
assert_not_contains "$print_output" " -t "

# --version prints the version string and exits without invoking docker.
: > "$DOCKER_LOG"
version_output="$(run_wrapper --version 2>&1)"
assert_contains "$version_output" "opencode-sandbox 0.1.1"
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
assert_contains "$legacy_output" "$legacy_home/.opencode-home/workspace:/opencode-home"

# Same workspace with the new per-slug sub-dir already present → no legacy warn.
clean_home="$TEST_TMP/clean-home"
mkdir -p "$clean_home/.opencode-home/workspace"
clean_output="$(
  cd "$TEST_WORKDIR"
  HOME="$clean_home" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox --print 2>&1
)"
assert_not_contains "$clean_output" "Legacy ~/.opencode-home/ state detected"

init_print_output="$(run_wrapper --init-structure --print 2>&1)"
assert_contains "$init_print_output" "docker run --rm -i --name opencode-workspace"
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
assert_contains "$pull_print_output" "docker run --rm -i --name opencode-workspace"

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
assert_contains "$space_output" "--name opencode-space-dir"

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
  assert_contains "$git_output" "--name opencode-git-root"
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
assert_contains "$docker_log_contents" "[opencode-workspace]"

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
