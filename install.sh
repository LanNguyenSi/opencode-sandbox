#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/opencode-sandbox"
TARGET_DIR="$HOME/.local/bin"
TARGET_SCRIPT="$TARGET_DIR/opencode-sandbox"
ADD_PATH=false
SHELL_RC=""

usage() {
  cat <<'USAGE'
Usage: install.sh [--add-path]

Options:
  --add-path   Add ~/.local/bin to the detected shell rc file if needed
  --help       Show this help
USAGE
}

detect_shell_rc() {
  case "${SHELL:-}" in
    */zsh)
      SHELL_RC="$HOME/.zshrc"
      ;;
    */bash)
      if [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
      else
        SHELL_RC="$HOME/.profile"
      fi
      ;;
    *)
      if [ -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bashrc"
      elif [ -f "$HOME/.zshrc" ]; then
        SHELL_RC="$HOME/.zshrc"
      else
        SHELL_RC="$HOME/.profile"
      fi
      ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --add-path)
      ADD_PATH=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$SOURCE_SCRIPT" ]; then
  echo "Error: '$SOURCE_SCRIPT' was not found."
  exit 1
fi

mkdir -p "$TARGET_DIR"
install -m 0755 "$SOURCE_SCRIPT" "$TARGET_SCRIPT"

echo "Installed: $TARGET_SCRIPT"

PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

case ":$PATH:" in
  *":$HOME/.local/bin:"*)
    echo "PATH already contains ~/.local/bin"
    ;;
  *)
    detect_shell_rc
    if [ "$ADD_PATH" = true ]; then
      touch "$SHELL_RC"
      if grep -Fqx "$PATH_LINE" "$SHELL_RC"; then
        echo "PATH entry is already present in $SHELL_RC"
      else
        printf '\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
        echo "Added PATH entry to $SHELL_RC"
      fi
      echo ""
      echo "Reload your shell:"
      echo "  source $SHELL_RC"
    else
      echo "PATH does not contain ~/.local/bin"
      echo "Add it manually or rerun with: ./install.sh --add-path"
      echo "Suggested shell file: $SHELL_RC"
    fi
    ;;
esac

echo ""
echo "After that, you can run:"
echo "  opencode-sandbox"
