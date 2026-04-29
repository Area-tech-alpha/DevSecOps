#!/usr/bin/env bash
set -euo pipefail

# Install the alpha-ci pre-push hook into a target git repository
# Usage: bash install-hook.sh [target-repo-path]

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TEMPLATE="$SCRIPT_DIR/pre-push-template"
TARGET_DIR="${1:-$(pwd)}"

if [ ! -f "$TEMPLATE" ]; then
  echo "pre-push template not found: $TEMPLATE"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Target directory does not exist: $TARGET_DIR"
  exit 1
fi

cd "$TARGET_DIR"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Target is not a git repository: $TARGET_DIR"
  exit 1
fi

HOOK_DIR="$TARGET_DIR/.git/hooks"
HOOK_PATH="$HOOK_DIR/pre-push"

mkdir -p "$HOOK_DIR"
cp "$TEMPLATE" "$HOOK_PATH"
chmod +x "$HOOK_PATH"

echo "Installed alpha-ci pre-push hook to: $HOOK_PATH"
echo "The hook runs alpha-ci without installing packages into the target project."
