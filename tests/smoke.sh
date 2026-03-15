#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

TEST_WORKDIR="$TEST_TMP/workspace"
FAKE_BIN="$TEST_TMP/fake-bin"
TEST_HOME="$TEST_TMP/home"

mkdir -p "$TEST_WORKDIR" "$FAKE_BIN" "$TEST_HOME"
cp "$ROOT_DIR/opencode-sandbox" "$TEST_WORKDIR/opencode-sandbox"
cp "$ROOT_DIR/PROJECT.md" "$TEST_WORKDIR/PROJECT.md"

cat > "$FAKE_BIN/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_BIN/docker" "$TEST_WORKDIR/opencode-sandbox"

run_wrapper() {
  (
    cd "$TEST_WORKDIR"
    HOME="$TEST_HOME" PATH="$FAKE_BIN:$PATH" bash ./opencode-sandbox "$@"
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
assert_contains "$print_output" "docker run -it --rm --name opencode-workspace"
assert_contains "$print_output" "ghcr.io/anomalyco/opencode:latest"
assert_contains "$print_output" "-v $TEST_HOME/.opencode-home:/opencode-home"
assert_contains "$print_output" "-e HOME=/opencode-home"
assert_contains "$print_output" "[opencode-sandbox][warn] No Git repository detected."
assert_contains "$print_output" "[opencode-sandbox][warn] AGENTS.md not found in workspace root."

init_print_output="$(run_wrapper --init-structure --print 2>&1)"
assert_contains "$init_print_output" "docker run -it --rm --name opencode-workspace"
assert_not_exists "$TEST_WORKDIR/.opencode-home"
assert_not_exists "$TEST_HOME/.opencode-home"
assert_not_exists "$TEST_WORKDIR/tasks"
assert_not_exists "$TEST_WORKDIR/context"
assert_not_exists "$TEST_WORKDIR/tmp"
assert_not_exists "$TEST_WORKDIR/outputs"

offline_output="$(run_wrapper --offline --print 2>&1)"
assert_contains "$offline_output" "--network none"

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

printf 'smoke tests: ok\n'
