#!/usr/bin/env bash
# Upload PR media to the `pr-assets` branch via the GitHub contents API
# and print one embeddable URL per file.
# Usage: upload-media.sh <issue-number> <file>...
# Must run inside a clone of the target repo with `gh` authenticated.
set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <issue-number> <file>..." >&2
  exit 2
fi

issue="$1"; shift
branch="pr-assets"
repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if ! gh api "repos/$repo/git/ref/heads/$branch" >/dev/null 2>&1; then
  default="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
  sha="$(gh api "repos/$repo/git/ref/heads/$default" -q .object.sha)"
  gh api "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$sha" >/dev/null
fi

body="$(mktemp)"
trap 'rm -f "$body"' EXIT

for file in "$@"; do
  [ -f "$file" ] || { echo "not a file: $file" >&2; exit 1; }
  path="$issue/$(basename "$file")"
  # Retry once: concurrent uploads from other issues can move the branch head (409).
  for attempt in 1 2; do
    # gh prints the error body on stdout for a 404, so keep only a real sha.
    existing="$(gh api "repos/$repo/contents/$path?ref=$branch" -q .sha 2>/dev/null)" || existing=""
    [[ "$existing" =~ ^[0-9a-f]{40}$ ]] || existing=""

    {
      printf '{"message":"chore: add PR media for #%s","branch":"%s",' "$issue" "$branch"
      [ -n "$existing" ] && printf '"sha":"%s",' "$existing"
      printf '"content":"'
      base64 < "$file" | tr -d '\n'
      printf '"}'
    } > "$body"

    if gh api -X PUT "repos/$repo/contents/$path" --input "$body" >/dev/null; then
      break
    fi
    [ "$attempt" = 2 ] && { echo "upload failed: $file" >&2; exit 1; }
    sleep 2
  done
  echo "https://github.com/$repo/blob/$branch/$path?raw=true"
done
