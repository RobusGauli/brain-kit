#!/bin/bash
# install.sh test. Runs the installer from this checkout into throwaway HOMEs,
# with a PATH that has no real `brain`, so it never touches the user's machine.
# The download path uses a fake curl that serves a local tarball.
# Runs every case under each of sh, dash and bash that exists.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FAILS=0
PASSES=0

fail() { echo "FAIL: [$SH] $*"; FAILS=$((FAILS+1)); }
ok()   { echo "ok:   [$SH] $*"; PASSES=$((PASSES+1)); }
assert_contains() { echo "$1" | grep -qF -- "$2" && ok "$3" || fail "$3 (missing '$2' in: $1)"; }
assert_missing()  { echo "$1" | grep -qF -- "$2" && fail "$3 (found '$2')" || ok "$3"; }

# A PATH with only basic tools. No `brain` from the real machine.
mkdir -p "$T/sysbin"
for tool in python3 mkdir rmdir mktemp cp mv rm ln readlink dirname find chmod tar gzip id uname; do
  p="$(command -v "$tool")" && ln -s "$p" "$T/sysbin/$tool"
done
# Fake curl. The "latest release" lookup (-I ... -w) prints a redirect target
# for tag $FAKE_LATEST (default v9.9.9), or fails when FAKE_LATEST_FAIL=1.
# A download writes $FAKE_TGZ to the -o path and logs the URL to $FAKE_LOG;
# FAKE_CURL_FAIL=1 fails it.
cat > "$T/sysbin/curl" <<'EOF'
#!/bin/sh
case " $* " in
  *" -fsSLI "*)
    [ "${FAKE_LATEST_FAIL:-}" = 1 ] && exit 22
    printf 'https://github.com/RobusGauli/brain-kit/releases/tag/%s' "${FAKE_LATEST:-v9.9.9}"; exit 0 ;;
esac
[ "${FAKE_CURL_FAIL:-}" = 1 ] && exit 22
for a in "$@"; do case "$a" in https://*) url=$a ;; esac; done
[ -n "${FAKE_LOG:-}" ] && printf '%s\n' "$url" >> "$FAKE_LOG"
while [ $# -gt 0 ]; do [ "$1" = -o ] && { cp "$FAKE_TGZ" "$2"; exit; }; shift; done
exit 2
EOF
chmod +x "$T/sysbin/curl"
# A tarball shaped like codeload's: one top folder, repo inside.
mkdir -p "$T/pkg/brain-kit-main/skills"
cp -R "$REPO/skills/second-brain" "$T/pkg/brain-kit-main/skills/"
mkdir -p "$T/pkg/brain-kit-main/skills/second-brain/scripts/__pycache__"
tar -czf "$T/src.tgz" -C "$T/pkg" brain-kit-main
# A source whose CLI is broken.
mkdir -p "$T/broken/skills"
cp -R "$REPO/skills/second-brain" "$T/broken/skills/"
printf '#!/usr/bin/env python3\nimport sys; sys.exit(3)\n' > "$T/broken/skills/second-brain/scripts/brain"
# A fake id that says root.
mkdir -p "$T/rootbin"
printf '#!/bin/sh\necho 0\n' > "$T/rootbin/id"; chmod +x "$T/rootbin/id"
# A fake uname that says Git Bash on Windows.
mkdir -p "$T/gitbash"
printf '#!/bin/sh\necho MINGW64_NT-10.0-19045\n' > "$T/gitbash/uname"; chmod +x "$T/gitbash/uname"

SHELLS=""
for s in sh dash bash; do command -v "$s" >/dev/null 2>&1 && SHELLS="$SHELLS $(command -v "$s")"; done

for SHBIN in $SHELLS; do
SH=$(basename "$SHBIN")
W="$T/$SH"; mkdir -p "$W"

inst() {  # inst HOME [env...]: run the installer from the local checkout
  local home="$1"; shift
  env -i HOME="$home" PATH="$T/sysbin" BRAIN_KIT_SOURCE="$REPO" "$@" "$SHBIN" "$REPO/install.sh" 2>&1
}

# ---- fresh install from the download path -----------------------------------
H="$W/h1"; mkdir -p "$H/.cursor" "$H/.kiro"
LOG="$W/curl.log"; : > "$LOG"
OUT=$(env -i HOME="$H" PATH="$T/sysbin" FAKE_TGZ="$T/src.tgz" FAKE_LOG="$LOG" "$SHBIN" "$REPO/install.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "download install exits 0" || fail "download install exit $RC: $OUT"
SKILL="$H/.local/share/brain-kit/skills/second-brain"
assert_contains "$(cat "$LOG")" "codeload.github.com/RobusGauli/brain-kit/tar.gz/v9.9.9" "downloads the latest release, not main"
assert_contains "$OUT" "source:    RobusGauli/brain-kit@v9.9.9" "prints the release it installed"
R="$H/.local/share/brain-kit/install.json"
RV=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["version"], d["source"], d["method"], d["installed_at"][:2])' "$R" 2>&1)
assert_contains "$RV" "$(python3 "$REPO/skills/second-brain/scripts/brain" --version | cut -d' ' -f2) RobusGauli/brain-kit@v9.9.9 install.sh 20" "writes the install receipt"

# A pin wins over the latest release: positional argument, then BRAIN_KIT_REF.
: > "$LOG"
env -i HOME="$H" PATH="$T/sysbin" FAKE_TGZ="$T/src.tgz" FAKE_LOG="$LOG" "$SHBIN" "$REPO/install.sh" v1.2.3 >/dev/null 2>&1
env -i HOME="$H" PATH="$T/sysbin" FAKE_TGZ="$T/src.tgz" FAKE_LOG="$LOG" BRAIN_KIT_REF=main "$SHBIN" "$REPO/install.sh" >/dev/null 2>&1
assert_contains "$(sed -n 1p "$LOG")" "tar.gz/v1.2.3" "positional argument pins the version"
assert_contains "$(sed -n 2p "$LOG")" "tar.gz/main" "BRAIN_KIT_REF pins the version"
[ -f "$SKILL/SKILL.md" ] && ok "skill extracted" || fail "skill not extracted"
for d in .claude .agents .cursor .kiro; do
  [ "$(readlink "$H/$d/skills/second-brain")" = "$SKILL" ] && ok "linked into $d" || fail "not linked into $d"
done
[ "$(readlink "$H/.local/bin/brain")" = "$SKILL/scripts/brain" ] && ok "cli linked" || fail "cli not linked"
[ -z "$(find "$SKILL" -name __pycache__)" ] && ok "no __pycache__" || fail "__pycache__ installed"
assert_contains "$OUT" "cli:       $SKILL/scripts/brain" "prints the cli path"
assert_contains "$OUT" "version:   second-brain" "prints the version"
assert_contains "$OUT" "done." "prints done."
[ -z "$(ls -A "$H/.local/share/brain-kit" | grep -vE '^(skills|install.json)$')" ] && ok "no stage or lock left" || fail "leftovers: $(ls -A "$H/.local/share/brain-kit")"

# ---- re-run updates in place --------------------------------------------------
echo stale > "$SKILL/stale-file"
OUT=$(inst "$H"); RC=$?
[ $RC -eq 0 ] && ok "re-run exits 0" || fail "re-run exit $RC: $OUT"
[ ! -e "$SKILL/stale-file" ] && ok "re-run replaces the old copy" || fail "old copy kept"
[ ! -e "$SKILL/second-brain" ] && ok "re-run does not nest" || fail "nested copy"

# ---- changed XDG_DATA_HOME repoints our own links -----------------------------
OUT=$(inst "$H" XDG_DATA_HOME="$W/xdg"); RC=$?
NEW="$W/xdg/brain-kit/skills/second-brain"
[ "$(readlink "$H/.claude/skills/second-brain")" = "$NEW" ] && ok "link repointed to new path" || fail "link not repointed: $OUT"
[ "$(readlink "$H/.local/bin/brain")" = "$NEW/scripts/brain" ] && ok "cli link repointed" || fail "cli link not repointed"

# ---- relative XDG_DATA_HOME is ignored ----------------------------------------
H="$W/h2"
OUT=$(cd "$W" && inst "$H" XDG_DATA_HOME=rel); RC=$?
[ "$(readlink "$H/.claude/skills/second-brain")" = "$H/.local/share/brain-kit/skills/second-brain" ] \
  && ok "relative XDG_DATA_HOME ignored" || fail "relative XDG_DATA_HOME used: $OUT"

# ---- never replaces what it did not create -----------------------------------
H="$W/h3"
mkdir -p "$H/.claude/skills/second-brain" "$H/.local/bin" "$H/.agents/skills" "$H/.cursor"
echo mine > "$H/.claude/skills/second-brain/SKILL.md"
ln -s /somewhere/else "$H/.agents/skills/second-brain"
echo "not a dir" > "$H/.cursor/skills"
printf '#!/bin/sh\necho other\n' > "$H/.local/bin/brain"
OUT=$(inst "$H"); RC=$?
[ $RC -eq 0 ] && ok "install beside foreign files exits 0" || fail "exit $RC: $OUT"
[ "$(cat "$H/.claude/skills/second-brain/SKILL.md")" = mine ] && ok "foreign folder left alone" || fail "foreign folder changed"
[ "$(readlink "$H/.agents/skills/second-brain")" = /somewhere/else ] && ok "foreign link left alone" || fail "foreign link changed"
[ "$(cat "$H/.local/bin/brain")" = "$(printf '#!/bin/sh\necho other')" ] && ok "foreign brain left alone" || fail "foreign brain changed"
assert_contains "$OUT" "skipped:   $H/.claude/skills/second-brain" "reports the folder skip"
assert_contains "$OUT" "skipped:   $H/.cursor/skills/second-brain (could not create it)" "odd skills folder is skipped"
assert_contains "$OUT" "done." "odd skills folder does not abort"

# ---- an existing `brain` on PATH keeps its name -------------------------------
H="$W/h4"; mkdir -p "$W/otherbin"
printf '#!/bin/sh\necho other\n' > "$W/otherbin/brain"; chmod +x "$W/otherbin/brain"
OUT=$(env -i HOME="$H" PATH="$T/sysbin:$W/otherbin" BRAIN_KIT_SOURCE="$REPO" "$SHBIN" "$REPO/install.sh" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "install with brain on PATH exits 0" || fail "exit $RC: $OUT"
[ ! -e "$H/.local/bin/brain" ] && ok "no ~/.local/bin/brain when brain is on PATH" || fail "shadowed brain"

# ---- failures exit non-zero, print no done., keep the old install --------------
H="$W/h5"; inst "$H" >/dev/null
check_fail() {  # check_fail NAME OUTPUT RC
  [ "$3" -ne 0 ] && ok "$1 exits non-zero" || fail "$1 exit 0: $2"
  assert_missing "$2" "done." "$1 prints no done."
  [ -f "$H/.local/share/brain-kit/skills/second-brain/SKILL.md" ] && ok "$1 keeps the old install" || fail "$1 lost the install"
}
OUT=$(inst "$H" BRAIN_KIT_SOURCE="$W/nothing"); check_fail "bad source" "$OUT" $?
OUT=$(env -i HOME="$H" PATH="$T/sysbin" FAKE_CURL_FAIL=1 "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "failed download" "$OUT" $?
: > "$W/curl2.log"
OUT=$(env -i HOME="$H" PATH="$T/sysbin" FAKE_LATEST_FAIL=1 FAKE_TGZ="$T/src.tgz" FAKE_LOG="$W/curl2.log" "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "no latest release" "$OUT" $?
assert_contains "$OUT" "could not find the latest brain-kit release" "no latest release explains itself"
[ ! -s "$W/curl2.log" ] && ok "no latest release does not fall back to main" || fail "downloaded anyway: $(cat "$W/curl2.log")"
OUT=$(env -i HOME="$H" PATH="$T/sysbin" FAKE_LATEST='../../evil' FAKE_TGZ="$T/src.tgz" "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "odd release tag" "$OUT" $?
echo "not a tarball" > "$W/bad.tgz"
OUT=$(env -i HOME="$H" PATH="$T/sysbin" FAKE_TGZ="$W/bad.tgz" "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "corrupt download" "$OUT" $?
OUT=$(inst "$H" BRAIN_KIT_SOURCE="$T/broken"); check_fail "broken cli" "$OUT" $?
mkdir "$H/.local/share/brain-kit/.lock"
OUT=$(inst "$H"); check_fail "concurrent install" "$OUT" $?
assert_contains "$OUT" "another brain-kit install is running" "concurrent install explains itself"
rmdir "$H/.local/share/brain-kit/.lock"
OUT=$(env -i HOME="$H" PATH="$T/rootbin:$T/sysbin" BRAIN_KIT_SOURCE="$REPO" "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "root" "$OUT" $?
OUT=$(env -i HOME="$H" PATH="$T/gitbash:$T/sysbin" BRAIN_KIT_SOURCE="$REPO" "$SHBIN" "$REPO/install.sh" 2>&1); check_fail "git bash" "$OUT" $?
assert_contains "$OUT" "install.ps1" "git bash points to install.ps1"
[ -z "$(ls -A "$H/.local/share/brain-kit" | grep -vE '^(skills|install.json)$')" ] && ok "failures leave no stage or lock" || fail "leftovers: $(ls -A "$H/.local/share/brain-kit")"

# ---- HOME unset ---------------------------------------------------------------
OUT=$(env -i PATH="$T/sysbin" BRAIN_KIT_SOURCE="$REPO" "$SHBIN" "$REPO/install.sh" 2>&1); RC=$?
[ $RC -ne 0 ] && ok "HOME unset exits non-zero" || fail "HOME unset exit 0"
assert_contains "$OUT" "HOME is not set" "HOME unset explains itself"

# ---- an interrupted swap is repaired by the next run --------------------------
S="$H/.local/share/brain-kit/skills/second-brain"
mv "$S" "$S.old"
OUT=$(inst "$H"); RC=$?
[ $RC -eq 0 ] && [ -f "$S/SKILL.md" ] && [ ! -e "$S.old" ] && ok "half-done swap repaired" || fail "swap not repaired: $OUT"

# ---- a script cut off at any line runs nothing --------------------------------
N=$(wc -l < "$REPO/install.sh")
BAD=0
for i in $(seq 1 $((N - 1))); do
  OUT=$(head -n "$i" "$REPO/install.sh" | env -i HOME="$H" PATH="$T/sysbin" BRAIN_KIT_SOURCE="$W/nothing" "$SHBIN" 2>&1)
  if echo "$OUT" | grep -qE 'installed:|done\.' || [ ! -f "$S/SKILL.md" ]; then BAD=$((BAD+1)); echo "  cut at line $i: $OUT"; fi
done
[ $BAD -eq 0 ] && ok "cut-off script runs nothing at all $((N - 1)) cut points" || fail "$BAD cut points ran part of the install"

done

# ---- online: the real download installs the latest release ------------------
# Set BRAIN_KIT_ONLINE_TEST=1 (CI does) to run it against GitHub.
if [ "${BRAIN_KIT_ONLINE_TEST:-}" = 1 ]; then
  SH=online
  AUTH=(); [ -n "${GITHUB_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")
  WANT=$(curl -fsSL "${AUTH[@]+"${AUTH[@]}"}" https://api.github.com/repos/RobusGauli/brain-kit/releases/latest \
         | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  PATHS="$T/sysbin-real"; mkdir -p "$PATHS"
  for tool in sh curl python3 mkdir rmdir mktemp cp mv rm ln readlink dirname find chmod tar gzip id uname; do
    p="$(command -v "$tool")" && ln -s "$p" "$PATHS/$tool"
  done
  OUT=$(env -i HOME="$T/online" PATH="$PATHS" "$(command -v sh)" "$REPO/install.sh" 2>&1)
  assert_contains "$OUT" "source:    RobusGauli/brain-kit@$WANT" "online install gets the latest release $WANT"
  assert_contains "$OUT" "done." "online install finishes"
  OUT=$(env -i HOME="$T/online" PATH="$PATHS" "$(command -v sh)" "$REPO/install.sh" v1.0.0 2>&1)
  assert_contains "$OUT" "version:   second-brain 1.0.0" "online install honours a pinned tag"

  # brain update: install this checkout, then update it to a real release.
  HU="$T/online-update"
  env -i HOME="$HU" PATH="$PATHS" BRAIN_KIT_SOURCE="$REPO" "$(command -v sh)" "$REPO/install.sh" >/dev/null 2>&1
  CLI="$HU/.local/share/brain-kit/skills/second-brain/scripts/brain"
  OUT=$(env -i HOME="$HU" PATH="$PATHS" python3 "$CLI" update --check 2>&1); RC=$?
  [ $RC -eq 0 ] && ok "update --check exits 0" || fail "update --check exit $RC: $OUT"
  assert_contains "$OUT" "latest:    $WANT" "update --check reports the latest release"
  OUT=$(env -i HOME="$HU" PATH="$PATHS" python3 "$CLI" update --to v1.0.0 2>&1); RC=$?
  [ $RC -eq 0 ] && ok "update --to exits 0" || fail "update --to exit $RC: $OUT"
  assert_contains "$(python3 "$CLI" --version)" "second-brain 1.0.0" "update --to installed that release in the same place"
  assert_contains "$(cat "$HU/.local/share/brain-kit/install.json")" "RobusGauli/brain-kit@v1.0.0" "update --to rewrote the receipt"
  OUT=$(cd "$T" && python3 -c "import sys; sys.path.insert(0, '$REPO/skills/second-brain/scripts'); from lib import update; sys.exit(update.run('0.0.1', check=True))" 2>&1)
  assert_contains "$OUT" "update available: 0.0.1 -> $WANT" "update --check sees a newer release"
fi

# ---- brain update on a copy the installer did not make (offline) -------------
SH=update
OUT=$(python3 "$REPO/skills/second-brain/scripts/brain" update --to v1.0.0 2>&1); RC=$?
[ $RC -eq 1 ] && ok "update refuses a copy it did not install" || fail "update on a foreign copy exit $RC: $OUT"
assert_contains "$OUT" "npx skills update" "update points to the right tool"
OUT=$(python3 "$REPO/skills/second-brain/scripts/brain" update --to '../x' 2>&1); RC=$?
[ $RC -eq 2 ] && ok "update --to rejects a non-tag" || fail "update --to ../x exit $RC: $OUT"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "INSTALL TEST PASS ($PASSES assertions;$SHELLS)"
else
  echo "INSTALL TEST FAIL ($FAILS failures, $PASSES passed)"
  exit 1
fi
