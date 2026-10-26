#!/bin/bash
# The version must agree everywhere: `brain --version`, the SKILL.md
# metadata.version, the newest CHANGELOG.md entry and, on a tag build, the tag.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO/skills/second-brain"

CLI=$(python3 "$SKILL/scripts/brain" --version | sed 's/^second-brain //')
META=$(sed -n '/^---$/,/^---$/p' "$SKILL/SKILL.md" | sed -n 's/^  version: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
LOG=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' "$REPO/CHANGELOG.md" | head -n 1)
TAG=""
case "${GITHUB_REF:-}" in refs/tags/v*) TAG="${GITHUB_REF#refs/tags/v}" ;; esac

echo "brain --version:          $CLI"
echo "SKILL.md metadata.version: $META"
echo "CHANGELOG.md newest:      $LOG"
[ -n "$TAG" ] && echo "git tag:                  $TAG"

ok=1
[ "$META" = "$CLI" ] || { echo "MISMATCH: SKILL.md metadata.version"; ok=0; }
[ "$LOG" = "$CLI" ]  || { echo "MISMATCH: CHANGELOG.md newest entry"; ok=0; }
[ -z "$TAG" ] || [ "$TAG" = "$CLI" ] || { echo "MISMATCH: git tag"; ok=0; }
[ $ok = 1 ] && echo "VERSION CHECK PASS" || { echo "VERSION CHECK FAIL"; exit 1; }
