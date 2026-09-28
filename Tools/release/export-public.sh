#!/usr/bin/env bash
# Writes the public copy of the project into <destination>: the committed files of HEAD without the internal
# ones (working notes, verification briefs, protocol dumps), then checks the copy for anything personal and fails
# when it finds some. It never pushes or uploads anything.
#
#   Tools/release/export-public.sh <destination>
#
# Personal words to look for (a name's email, a device, a team ID…) go one per line, as extended regular
# expressions, into Tools/release/private-patterns.txt. That file is ignored by git and never exported.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${1:?usage: export-public.sh <destination>}"
PRIVATE_PATTERNS="$ROOT/Tools/release/private-patterns.txt"

# Kept in the private repository only.
INTERNAL=(
  docs/TESTING.md
  docs/CODEX-VERIFY.md
  docs/spikes
  STACK-OVERVIEW.md
  .claude
  AGENTS.md
  CLAUDE.md
  Tools/release/private-patterns.txt
)

# What must never be public, whoever the author is.
GENERIC=(
  '/Users/[a-z][a-z0-9._-]*/'                    # a home folder
  'DEVELOPMENT_TEAM: *[A-Z0-9]{10}'               # an Apple team ID written into the project
  'Apple (Development|Distribution): '            # a signing certificate's name
  'BEGIN [A-Z ]*PRIVATE KEY'
  '[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}'              # a Telegram bot token
  'sk-(ant-)?[A-Za-z0-9_-]{24,}'                  # an OpenAI or Anthropic key
  'AKIA[0-9A-Z]{16}'                              # an AWS key
  'hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]{12,}'
)

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
  echo "$DEST is not empty; choose a new folder" >&2
  exit 2
fi
mkdir -p "$DEST"

cd "$ROOT"
if [ -n "$(git status --porcelain)" ]; then
  echo "note: only committed files are exported; uncommitted changes are left out" >&2
fi
git archive HEAD | tar -x -C "$DEST"
for path in "${INTERNAL[@]}"; do
  rm -rf "${DEST:?}/$path"
done

patterns=("${GENERIC[@]}")
if [ -f "$PRIVATE_PATTERNS" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] && [ "${line#\#}" = "$line" ] && patterns+=("$line")
  done <"$PRIVATE_PATTERNS"
else
  echo "note: $PRIVATE_PATTERNS is missing; only the generic checks run" >&2
fi

found=0
for pattern in "${patterns[@]}"; do
  if hits="$(grep -rIniE -- "$pattern" "$DEST" 2>/dev/null)"; then
    found=1
    # Show where, not what: the match itself may be the secret.
    echo "$hits" | cut -d: -f1-2 | sed "s|^$DEST/|  |" >&2
  fi
done
if [ "$found" -eq 1 ]; then
  echo "personal or secret data found in the lines above; nothing is ready to publish" >&2
  exit 1
fi

echo "public copy: $DEST ($(find "$DEST" -type f | wc -l | tr -d ' ') files), checked clean"
