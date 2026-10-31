#!/usr/bin/env bash
# Symlink every skill in ./skills into the Claude Code user skills directory.
# Safe to re-run: existing links are refreshed, real directories are left alone.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)/skills"
dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
mkdir -p "$dest"

for dir in "$src"/*/; do
  name="$(basename "$dir")"
  target="$dest/$name"
  if [ -L "$target" ]; then
    ln -sfn "${dir%/}" "$target"
    echo "updated  $name"
  elif [ -e "$target" ]; then
    echo "skipped  $name — $target already exists and is not a symlink" >&2
  else
    ln -s "${dir%/}" "$target"
    echo "linked   $name"
  fi
done

chmod +x "$src"/*/scripts/*.sh 2>/dev/null || true
echo "done. Restart Claude Code to load new skills."
