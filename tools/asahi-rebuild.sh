#!/bin/bash
# Rebuild an Ubuntu Asahi branch for a new stable level / kernel base (AGENTS.md case 2).
#
# Drops only the old Asahi stack, keeps every other commit, and replays the new stack. Layers of
# an Ubuntu Asahi branch, bottom to top:
#   generic Ubuntu base (+ stable)  |  packaging (debian.asahi-arm ...)  |  Asahi stack  |  top
# The packaging sits below the stack so it shows the included commits properly. "Top" is Ubuntu
# commits that edit stack files (e.g. SAUCE), the Asahi config enablement commit and, last, the
# marker commit. See the asahi-port skill. Never pushes.
#
# Required env:
#   UBUNTU_REPO  the ubuntu-asahi tree (must contain LINUX_TAG and ASAHI_TAG). All work happens
#                in this tree itself (cranky needs that directory), so it must be clean
#   OLD          existing Ubuntu Asahi branch/commit to start from (e.g. asahi-arm-7.2)
#   LINUX_TAG    target stable tag (e.g. v7.2.14)
#   ASAHI_TAG    Asahi tag to port (e.g. asahi-7.2.14-1)
# Optional env:
#   BRANCH       result branch (default: asahi-rebuild); BRANCH-layers holds the new base
#   GENERIC      generic Ubuntu base commit (default: nearest first-parent 'UBUNTU: Ubuntu-<digit>')
#   KEEP_TOP     1 to carry commits that sat above the old stack and edit stack files (e.g. the
#                rust-io SAUCE). Default: drop them; they are fixups for that patchset version
#                (regenerate with the asahi-merge-review skill) and are listed in the output.
#   DATE         marker date (default: today); other asahi-port.sh env passes through
#   FEDORA_CLONE clone of fedora-asahi/kernel-asahi (see the asahi-crank skill). If set, Asahi config
#                enablement entries Ubuntu lacks are committed above the stack, before the marker
#   MARKER_FILE, PKG_PATHS   see lib.sh
#   GIT_AUTHOR_*/GIT_COMMITTER_*  default: author of OLD's tip
# Re-run with the same env after resolving a stop; finished phases are skipped.
set -u
: "${UBUNTU_REPO:?}" "${OLD:?}" "${LINUX_TAG:?}" "${ASAHI_TAG:?}"
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# Informational: say when the tag is ahead of Fedora Asahi (never blocks).
note_fedora "$ASAHI_TAG" "$UBUNTU_REPO" >&2
UBUNTU_REPO=$(cd "$UBUNTU_REPO" && pwd -P) || exit 1          # absolute: the tools cd into it
BRANCH=${BRANCH:-asahi-rebuild}; LAYERS=$BRANCH-layers
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MARK="Asahi patchset $ASAHI_TAG"
die() { echo "STOP: $*" >&2; exit 1; }
# Subject of commit $1 in the repo.
subject() { git log -1 --format=%s "$1"; }
# Has the new stack already been replayed and marked on BRANCH (a re-run after it finished)?
replayed() { [ "$(git branch --show-current)" = "$BRANCH" ] && ! pick_pending >/dev/null && [ "$(subject HEAD)" = "$MARK" ]; }

# --- 1. find the layers of OLD ------------------------------------------------------------
# Sets GENERIC (generic base), F (first stack commit), PKG_TIP (top of packaging), L (last stack
# commit), and sorts the non-Asahi commits above the stack into BELOW (packaging-only; they can
# go under the new stack) and TOP (they edit other files; they must go above it).
find_layers() {
  GENERIC=${GENERIC:-$(git log --first-parent -1 --format=%H --grep='^UBUNTU: Ubuntu-[0-9]' "$OLD")}
  [ -n "$GENERIC" ] || die "no generic base found; set GENERIC"
  F=$(git log --reverse --topo-order --no-merges --format=%H \
      --grep='cherry picked from\|backported from' "$GENERIC..$OLD" | head -1)
  [ -n "$F" ] || die "no Asahi stack found above $GENERIC"
  PKG_TIP=$(git rev-parse "$F^")
  [ "$(git rev-list --merges --count "$F^..$OLD")" = 0 ] || die "merges above the packaging; not handled"

  # The stack runs from F up to the commit before the first "UBUNTU:"/"Asahi patchset" commit.
  local R i c split=""
  mapfile -t R < <(git log --reverse --topo-order --format='%H %s' "$F^..$OLD")
  for i in "${!R[@]}"; do
    case "${R[$i]#* }" in "UBUNTU:"*|"Asahi patchset"*) split=$i; break;; esac
  done
  [ -n "$split" ] || die "no Ubuntu commit above the stack"
  STACK_LEN=$split
  L=${R[$((split-1))]%% *}
  git log --format= --name-only "$PKG_TIP..$L" | grep -q '^debian' && die "debian files inside the stack range $F..$L"

  BELOW=(); TOP=()
  for ((i = split; i < ${#R[@]}; i++)); do
    c=${R[$i]%% *}
    if git diff-tree --no-commit-id --name-only -r "$c" | grep -qvE "$PKG_PATHS"; then
      TOP+=("$c"); else BELOW+=("$c"); fi
  done
}

# Drop (and list) above-stack source fixups unless KEEP_TOP=1, then print the layer summary.
report_layers() {
  if [ "${KEEP_TOP:-0}" != 1 ] && [ ${#TOP[@]} -gt 0 ]; then
    DROPPED_TOP=("${TOP[@]}"); TOP=()
    for c in "${DROPPED_TOP[@]}"; do
      echo "dropped (per-version fixup; re-run asahi-merge-review): $(git log -1 --format='%h %s' "$c" | cut -c1-80)"
    done
  fi
  echo "generic base $(git log -1 --format='%h %s' "$GENERIC" | cut -c1-60)"
  echo "old stack $STACK_LEN commits ($(cut -c1-12 <<<"$F")..$(cut -c1-12 <<<"$L")); keep below: ${#BELOW[@]}, above: ${#TOP[@]}"
  for c in ${TOP[@]+"${TOP[@]}"}; do echo "  above stack: $(git log -1 --format='%h %s' "$c" | cut -c1-80)"; done
}

# --- 2. new base + packaging + kept commits ----------------------------------------------
# Branch LAYERS = LINUX_TAG merged into the generic base, the packaging rebased onto it, then the
# kept non-Asahi commits. Skipped if LAYERS already exists (re-run).
build_layers() {
  git rev-parse -q --verify "refs/heads/$LAYERS" >/dev/null && return 0
  git merge-tree --write-tree --name-only --no-messages "$GENERIC" "$LINUX_TAG" >/dev/null ||
    die "merging $LINUX_TAG into the generic base conflicts (git merge-tree to inspect)"
  [ -z "$(git status --porcelain --untracked-files=no)" ] || die "$UBUNTU_REPO has uncommitted changes"
  git checkout -q -b "$LAYERS" "$GENERIC" || die "cannot create $LAYERS"
  ( git merge --no-ff -q -m "Merge tag '$LINUX_TAG' into $(subject "$GENERIC" | sed 's/^UBUNTU: //') base" "$LINUX_TAG" >/dev/null || exit 1
    local newbase c; newbase=$(git rev-parse HEAD)
    git reset -q --hard "$PKG_TIP"
    git rebase --onto "$newbase" "$GENERIC" >/dev/null 2>&1 || { echo "packaging rebase conflicts"; exit 1; }
    for c in ${BELOW[@]+"${BELOW[@]}"}; do
      git cherry-pick "$c" >/dev/null 2>&1 || { echo "cherry-pick conflict: $c"; exit 1; }
    done ) || die "layers phase failed (left on branch $LAYERS in $UBUNTU_REPO for inspection; delete the branch to retry)"
}

# --- 3. replay the new stack (asahi-port.sh also commits the marker) -----------------------
replay_new_stack() {
  replayed && return 0                          # already replayed (re-run)
  UBUNTU_REPO=$UBUNTU_REPO BASE=$LAYERS LINUX_TAG=$LINUX_TAG ASAHI_TAG=$ASAHI_TAG \
    BRANCH=$BRANCH "$HERE/asahi-port.sh" 2>&1 |
    grep -vE '^  [0-9a-f]{12} Merge|^merges with' | tail -8
  replayed || die "port stopped: resolve in $UBUNTU_REPO (see asahi-conflicts skill), git add, re-run this script"
}

# --- 4. commits above the stack, then the marker last --------------------------------------
# Above the stack, in order: kept source fixups (TOP), then the Asahi config enablement commit
# (when FEDORA_CLONE is set), then the marker. Does nothing if all of that is already in place.
config_check() { python3 "$HERE/asahi-config-check.py" --fedora "$FEDORA_CLONE" --repo . --ubuntu HEAD "$@"; }

add_top_commits() {
  local c marker need_top=0 need_cfg=0
  for c in ${TOP[@]+"${TOP[@]}"}; do
    git log --format=%s "$NEWBASE..HEAD" | grep -qxF "$(subject "$c")" || need_top=1
  done
  if [ -z "${FEDORA_CLONE:-}" ]; then
    echo "config: FEDORA_CLONE not set; run tools/asahi-config-check.py after this (skill asahi-crank)"
  elif config_check | grep -q '=> add$'; then need_cfg=1
  else echo "config: no Asahi options to add"
  fi
  [ "$need_top$need_cfg" != 00 ] || return 0

  marker=$(git rev-parse HEAD); git reset -q --hard HEAD~1       # lift the marker
  if [ "$need_top" = 1 ]; then
    for c in "${TOP[@]}"; do
      git cherry-pick "$c" >/dev/null 2>&1 ||
        die "conflict applying $c above the stack in $UBUNTU_REPO (resolve, git cherry-pick --continue, then: git checkout $marker -- $MARKER_FILE; git commit -s -m '$MARK')"
    done
  fi
  if [ "$need_cfg" = 1 ]; then config_check --apply --commit | grep '^applied' | sed 's/^/config: /'; fi
  git checkout "$marker" -- "$MARKER_FILE" && git commit -q -s -m "$MARK"
}

# --- 5. verify ---------------------------------------------------------------------------
# (a) every non-stack commit of OLD (by subject) is present; (b) the stack files that differ
# from ASAHI_TAG, against the baseline of the same check on OLD ("new-only" needs attention).
verify() {
  local T oldv oldtag c
  T=$(mktemp -d)
  { git log --no-merges --format=%s "$GENERIC..$PKG_TIP"
    for c in ${BELOW[@]+"${BELOW[@]}"} ${TOP[@]+"${TOP[@]}"}; do subject "$c"; done; } | sort > "$T/exp"
  git log --no-merges --format=%s "$NEWBASE..HEAD" | sort > "$T/got"
  echo "missing non-stack commits: $(comm -23 "$T/exp" "$T/got" | wc -l) of $(wc -l < "$T/exp")"

  oldv=v$(git show "$OLD:Makefile" | makefile_version)
  oldtag=$(git show "$OLD:$MARKER_FILE" | grep -oE 'asahi-[0-9]+(\.[0-9]+)+-[0-9]+' | sort -V | tail -1)
  git diff --name-only "$LINUX_TAG" "$ASAHI_TAG" > "$T/files"
  git diff --name-only "$oldv" "$oldtag" > "$T/oldfiles"
  git diff --name-only "$oldtag" "$OLD" -- $(cat "$T/oldfiles") | sort > "$T/base"
  git diff --name-only "$ASAHI_TAG" HEAD -- $(cat "$T/files") | sort > "$T/new"
  echo "stack files differing from $ASAHI_TAG: $(wc -l < "$T/new") (baseline $OLD vs $oldtag: $(wc -l < "$T/base")); new-only: $(comm -13 "$T/base" "$T/new" | tr '\n' ' ')"
  rm -rf "$T"
}

main() {
  cd "$UBUNTU_REPO" || die "cannot enter $UBUNTU_REPO"
  default_identity "$UBUNTU_REPO" "$OLD"
  git rev-parse -q --verify "$LINUX_TAG^{commit}" >/dev/null || die "$LINUX_TAG not in repo (git fetch URL tag $LINUX_TAG)"
  git rev-parse -q --verify "$ASAHI_TAG^{commit}" >/dev/null || die "$ASAHI_TAG not in repo"
  find_layers
  report_layers
  build_layers
  NEWBASE=$(git merge-base "$LAYERS" "$LINUX_TAG")
  replay_new_stack
  add_top_commits
  verify
  echo "done: branch $BRANCH, tip $(git log -1 --format='%h %s')"
}
main
