#!/bin/sh
# brain-kit installer: puts the second-brain skill where coding agents find it.
#
#   curl -fsSL https://raw.githubusercontent.com/RobusGauli/brain-kit/main/install.sh | sh
#
# What it does (safe to re-run; re-running updates the code):
#   1. checks for python3 >= 3.9
#   2. downloads the repo and keeps skills/second-brain/ under
#      ${XDG_DATA_HOME:-~/.local/share}/brain-kit/
#   3. links that folder into ~/.claude/skills/ and ~/.agents/skills/
#      (and ~/.cursor/skills/, ~/.kiro/skills/ when those tools are present)
#   4. links the CLI to ~/.local/bin/brain, unless a `brain` command already exists
#
# It never touches your vaults or your config, and never replaces a file or
# link it did not create. It does not run `brain init`.
#
# Output contract (agents read it): one `installed:` line, then `linked:` /
# `skipped:` lines, then `cli: <path>`, `version: <v>` and a final `done.`.
# No `done.` line means the install did not finish.
#
# Overrides: BRAIN_KIT_REF (branch or tag, default main),
#            BRAIN_KIT_SOURCE (a local checkout to install from, for testing),
#            BRAIN_KIT_ALLOW_ROOT=1 (install as root on purpose).
#
# The whole body is a function called on the last line, so a download that
# stops part-way runs nothing.

main() {
  set -eu
  REPO="RobusGauli/brain-kit"
  REF="${BRAIN_KIT_REF:-main}"

  [ -n "${HOME:-}" ] || die "HOME is not set."
  case "$(uname -s 2>/dev/null)" in
    MINGW* | MSYS* | CYGWIN*)  # ln -s copies here, so re-runs could not update
      die "on Windows, run this in PowerShell instead: irm https://raw.githubusercontent.com/$REPO/main/install.ps1 | iex" ;;
  esac
  case "${XDG_DATA_HOME:-}" in
    /*) DATA="$XDG_DATA_HOME/brain-kit" ;;
    *)  DATA="$HOME/.local/share/brain-kit" ;;  # unset or relative: XDG says ignore
  esac
  SKILL="$DATA/skills/second-brain"
  BIN_DIR="$HOME/.local/bin"

  if [ "$(id -u)" = 0 ] && [ "${BRAIN_KIT_ALLOW_ROOT:-}" != 1 ]; then
    die "do not run this as root or with sudo. It installs for your own user. (Set BRAIN_KIT_ALLOW_ROOT=1 to do it anyway.)"
  fi

  # 1. python3 >= 3.9
  command -v python3 >/dev/null 2>&1 \
    || die "python3 not found. Install Python 3.9 or newer, then run this again."
  PYV=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null) || PYV=
  [ -n "$PYV" ] \
    || die "python3 does not run. On macOS, install the Command Line Tools (xcode-select --install) or Python from python.org."
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' \
    || die "python3 is $PYV; brain-kit needs 3.9 or newer."

  # One install at a time. Stage on the same filesystem so the swap is a rename.
  mkdir -p "$DATA/skills"
  mkdir "$DATA/.lock" 2>/dev/null \
    || die "another brain-kit install is running. If none is, delete $DATA/.lock and run this again."
  LOCKED=1
  STAGE=$(mktemp -d "$DATA/.stage.XXXXXX")

  # Finish a swap that an earlier run did not finish.
  if [ -d "$SKILL.old" ]; then
    if [ -e "$SKILL" ]; then rm -rf "$SKILL.old"; else mv "$SKILL.old" "$SKILL"; fi
  fi

  # 2. fetch
  if [ -n "${BRAIN_KIT_SOURCE:-}" ]; then
    [ -f "$BRAIN_KIT_SOURCE/skills/second-brain/SKILL.md" ] \
      || die "BRAIN_KIT_SOURCE=$BRAIN_KIT_SOURCE has no skills/second-brain/SKILL.md"
    cp -R "$BRAIN_KIT_SOURCE/skills/second-brain" "$STAGE/second-brain"
  else
    command -v curl >/dev/null 2>&1 || die "curl not found."
    curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$REF" -o "$STAGE/src.tgz" \
      || die "could not download $REPO@$REF."
    mkdir "$STAGE/src"
    tar -xzf "$STAGE/src.tgz" -C "$STAGE/src" --strip-components=1 \
      || die "the download of $REPO@$REF is not a valid archive."
    [ -f "$STAGE/src/skills/second-brain/SKILL.md" ] \
      || die "the download has no skills/second-brain/SKILL.md."
    mv "$STAGE/src/skills/second-brain" "$STAGE/second-brain"
  fi
  find "$STAGE/second-brain" \( -name __pycache__ -o -name '*.pyc' \) -prune -exec rm -rf {} +
  chmod +x "$STAGE/second-brain/scripts/brain"
  VERSION=$(python3 -B "$STAGE/second-brain/scripts/brain" --version 2>&1) \
    || die "the downloaded CLI does not run: $VERSION"

  # Swap. Each step is a rename; a crash between them is repaired by the next run.
  [ -e "$SKILL" ] && mv "$SKILL" "$SKILL.old"
  mv "$STAGE/second-brain" "$SKILL"
  rm -rf "$SKILL.old"
  say "installed: $SKILL"

  # 3 + 4. links
  link "$SKILL" "$HOME/.claude/skills/second-brain"   # Claude Code
  link "$SKILL" "$HOME/.agents/skills/second-brain"   # Codex, Cursor
  if [ -d "$HOME/.cursor" ]; then link "$SKILL" "$HOME/.cursor/skills/second-brain"; fi
  if [ -d "$HOME/.kiro" ];   then link "$SKILL" "$HOME/.kiro/skills/second-brain"; fi

  if [ -L "$BIN_DIR/brain" ] && ours "$(readlink "$BIN_DIR/brain")"; then
    link "$SKILL/scripts/brain" "$BIN_DIR/brain"
  elif [ -e "$BIN_DIR/brain" ] || [ -L "$BIN_DIR/brain" ] || command -v brain >/dev/null 2>&1; then
    say "skipped:   $BIN_DIR/brain (a different 'brain' command exists; use the cli path)"
  else
    link "$SKILL/scripts/brain" "$BIN_DIR/brain"
  fi

  say "cli:       $SKILL/scripts/brain"
  say "version:   $VERSION"
  say "next:      ask the user for their work vault folder, personal vault folder and name, then run"
  say "           python3 \"$SKILL/scripts/brain\" init --work-vault <work-folder> --personal-vault <personal-folder> --owner \"<Full Name>\""
  say "done."
}

say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  [ -n "${STAGE:-}" ] && rm -rf "$STAGE"
  [ -n "${LOCKED:-}" ] && rmdir "$DATA/.lock" 2>/dev/null
  return 0
}

# A link target is brain-kit's if it is a brain-kit skill copy or its CLI,
# wherever an earlier run put it.
ours() {
  case "$1" in
    */brain-kit/skills/second-brain | */brain-kit/skills/second-brain/scripts/brain) return 0 ;;
    *) return 1 ;;
  esac
}

link() {  # link TARGET LINKPATH: create or repoint, but only an empty slot or our own link
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]; then
    say "linked:    $2"
  elif [ -L "$2" ] && ours "$(readlink "$2")"; then
    old=$(readlink "$2")   # an older brain-kit install path
    ln -sfn "$1" "$2"
    say "linked:    $2 (updated from $old)"
  elif [ -e "$2" ] || [ -L "$2" ]; then
    say "skipped:   $2 (already exists and is not brain-kit's; left it alone)"
  elif ! mkdir -p "$(dirname "$2")" 2>/dev/null || ! ln -s "$1" "$2" 2>/dev/null; then
    say "skipped:   $2 (could not create it)"
  else
    say "linked:    $2"
  fi
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

main "$@"
