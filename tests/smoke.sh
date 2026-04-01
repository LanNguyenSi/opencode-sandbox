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
assert_contains "$print_output" "ghcr.io/anomalyco/opencode:latest"
assert_contains "$print_output" "-v $TEST_HOME/.opencode-home:/opencode-home"
assert_contains "$print_output" "-e HOME=/opencode-home"
assert_contains "$print_output" "[opencode-sandbox][warn] No Git repository detected."
assert_contains "$print_output" "[opencode-sandbox][warn] AGENTS.md not found in workspace root."
assert_not_contains "$print_output" " -t "

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
assert_contains "$pull_print_output" "docker pull ghcr.io/anomalyco/opencode:latest"
assert_contains "$pull_print_output" "docker run --rm -i --name opencode-workspace"

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
assert_contains "$docker_log_contents" "[pull]"
assert_contains "$docker_log_contents" "[ghcr.io/anomalyco/opencode:latest]"
assert_contains "$docker_log_contents" "[run]"
assert_contains "$docker_log_contents" "[--name]"
assert_contains "$docker_log_contents" "[opencode-workspace]"

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
assert_contains "$(cat "$INSTALL_TEST_HOME/.bashrc")" 'export PATH="$HOME/.local/bin:$PATH"'

printf 'smoke tests: ok\n'
