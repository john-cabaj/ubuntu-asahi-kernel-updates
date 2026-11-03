#!/bin/bash
# Replay the Asahi Linux patch stack onto an Ubuntu Asahi tree (AGENTS.md case 2/3 helper).
#
# Replays the whole stack as Asahi does on a new Linux base, adding the upstream URL to each
# commit's provenance trailer in the same pass, then records the port with a marker commit.
# Never pushes. Use tools/asahi-rebuild.sh to build BASE and handle the layers around the stack.
#
# Required env:
#   UBUNTU_REPO   path to the ubuntu-asahi clone (must already contain the Asahi tags/objects)
#   BASE          Ubuntu commit to start from (the commit just before the first Asahi patch)
#   LINUX_TAG     Linux tag the Asahi tag is based on (e.g. v7.2.12)
#   ASAHI_TAG     Asahi tag to port (e.g. asahi-7.2.12-2)
#   WORKTREE      the tree to work in; set equal to UBUNTU_REPO (a separate dir becomes a git worktree)
# Optional env:
#   BRANCH        new branch name (default: asahi-port)
#   KEEP_UBUNTU_FILES  space-separated files where, on conflict, Ubuntu's hunks are kept
#                 (opt-in policy; commits left empty by this are skipped). Unverified.
#   NOTE_NAME     reviewer name for the backport note "[name: context changes]". Default: unset,
#                 and resolved picks get the unreviewed note (lib.sh) for tools/asahi-review.sh.
#                 Set it only for work that person has reviewed.
#   URL           provenance URL (default: https://github.com/AsahiLinux/linux)
#   DATE          date in the marker line (default: today, YYYY-MM-DD)
#   LOG           log file (default: $WORKTREE.conflicts.log)
#   GIT_AUTHOR_*/GIT_COMMITTER_*  identity (the repo may have none configured)
#
# Stops (prints STOP) at each unresolved conflict: resolve, `git add`, and re-run with the same
# env. A re-run resumes the pending pick and never replays what already landed or was skipped.
set -u
: "${UBUNTU_REPO:?}" "${BASE:?}" "${LINUX_TAG:?}" "${ASAHI_TAG:?}" "${WORKTREE:?}"
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# Informational: say when the tag is ahead of Fedora Asahi (never blocks).
note_fedora "$ASAHI_TAG" "$UBUNTU_REPO" >&2
BRANCH=${BRANCH:-asahi-port}; URL=${URL:-https://github.com/AsahiLinux/linux}
KEEP_UBUNTU_FILES=${KEEP_UBUNTU_FILES:-}
NOTE_NAME=${NOTE_NAME:-}
if [ -n "$NOTE_NAME" ]; then NOTE_TEXT="[$NOTE_NAME: context changes]"; else NOTE_TEXT=$UNREVIEWED_NOTE; fi
LOG=${LOG:-$WORKTREE.conflicts.log}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE=$(mktemp -d "${TMPDIR:-/tmp}/asahi-port.XXXXXX"); trap 'rm -rf "$STATE"' EXIT
export URL STATE NOTE_TEXT

log() { echo "$*" | tee -a "$LOG"; }
pick_pending() { git rev-parse -q --verify CHERRY_PICK_HEAD; }
unmerged() { git diff --name-only --diff-filter=U; }
# Source commits already applied on top of BASE, by provenance trailer.
landed() { git log --format=%B "$BASE..HEAD" | trailer_shas; }

# --- setup -------------------------------------------------------------------------------
# Commit-message editor for `cherry-pick -e`: adds the provenance URL to the
# "(cherry picked|backported) from commit" line. While $STATE/BACKPORT_ONCE exists the commit is
# a conflict resolution: relabel it "backported" and add the note NOTE_TEXT.
# The flag is one-shot because the editor setting persists across `cherry-pick --continue`.
install_msgfix() {
  cat > "$STATE/msgfix" <<'EOS'
#!/bin/sh
f=$1
if [ -f "$STATE/BACKPORT_ONCE" ]; then
  rm -f "$STATE/BACKPORT_ONCE"
  sed -Ei 's#^\(cherry picked from commit#(backported from commit#' "$f"
  BP=1
fi
sed -Ei "s#^\((cherry picked|backported) from commit ([0-9a-f]+)\)\$#(\1 from commit \2 $URL)#" "$f"
[ -n "${BP:-}" ] && sed -Ei "/^\\(backported from commit/a $NOTE_TEXT" "$f"
exit 0
EOS
  chmod +x "$STATE/msgfix"
  export GIT_EDITOR="$STATE/msgfix"
}

setup_worktree() {
  if [ "$(cd "$WORKTREE" 2>/dev/null && pwd -P)" = "$(cd "$UBUNTU_REPO" && pwd -P)" ]; then
    # Working in the supplied tree itself (required by cranky's handle layout): switch it to BRANCH.
    git -C "$UBUNTU_REPO" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null ||
      git -C "$UBUNTU_REPO" checkout -q -b "$BRANCH" "$BASE" || exit 1
    git -C "$UBUNTU_REPO" checkout -q "$BRANCH" || exit 1
  else
    [ -d "$WORKTREE" ] || git -C "$UBUNTU_REPO" worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE" || exit 1
  fi
  cd "$WORKTREE" || exit 1
  # rerere replays earlier hand resolutions (cache: $GIT_DIR/rr-cache); autoUpdate stages them.
  git config rerere.enabled true; git config rerere.autoUpdate true
  : > "$LOG"
  # Commits that did not land (empty picks) are remembered here so a re-run does not retry,
  # and re-conflict on, them.
  SKIPFILE=$(git rev-parse --absolute-git-dir)/asahi-skipped; touch "$SKIPFILE"
}

# --- replay ------------------------------------------------------------------------------
# Cherry-pick every Asahi commit not yet landed or skipped.
replay_stack() {
  # Whole stack, linear, oldest first. --empty=drop skips patches already in the base.
  git rev-list --reverse --topo-order --no-merges "$LINUX_TAG..$ASAHI_TAG" > "$STATE/list" || exit 1
  { landed; cat "$SKIPFILE"; } > "$STATE/done"
  grep -vxFf "$STATE/done" "$STATE/list" > "$STATE/todo" || true
  log "$(wc -l < "$STATE/list") Asahi commits, $(wc -l < "$STATE/todo") to apply"
  [ -s "$STATE/todo" ] && git cherry-pick -e -x -s --empty=drop $(cat "$STATE/todo") >> "$LOG" 2>&1
}

# Commit the staged resolution of pick $1, or skip the pick if it became empty (the change is
# already in the tree). Returns 1 if the pick is still pending afterwards, so callers never loop.
finish() {
  local c=$1
  git rerere >/dev/null 2>&1 || true            # record the resolution for later replay
  if git diff --cached --quiet; then
    log "  empty after resolution; skipped $c"; echo "$c" >> "$SKIPFILE"
    git cherry-pick --skip >> "$LOG" 2>&1
  else
    touch "$STATE/BACKPORT_ONCE"                # tell msgfix this commit is a resolution
    git cherry-pick --continue >> "$LOG" 2>&1
  fi
  [ "$(pick_pending)" != "$c" ] || { log "STOP $c: could not finish pick (see $LOG)"; return 1; }
}

# True if every given file is listed in KEEP_UBUNTU_FILES.
all_in_keep_list() {
  [ -n "$KEEP_UBUNTU_FILES" ] || return 1
  for f in "$@"; do case " $KEEP_UBUNTU_FILES " in *" $f "*) ;; *) return 1;; esac; done
}

# Keep Ubuntu's hunks in every conflicted file (policy, only for KEEP_UBUNTU_FILES).
resolve_keep_ubuntu() {
  for f in "$@"; do
    git checkout -q -m -- "$f"
    "$HERE/conflict-side.py" ours "$f" && git add "$f"
  done
}

# Work through pending picks until none remain or one needs a human.
resolve_loop() {
  local c stall="" f files
  while c=$(pick_pending); do
    [ "$c" != "$stall" ] || { log "STOP $c: no progress"; break; }
    stall=$c
    # Unmerged paths without conflict markers were resolved by rerere (or by hand): stage them.
    for f in $(unmerged); do
      grep -q '^<<<<<<< ' "$f" 2>/dev/null || { git add "$f"; log "CONFLICT $c $f -> resolved by rerere/hand"; }
    done
    files=$(unmerged)
    if [ -n "$files" ]; then
      all_in_keep_list $files || { log "STOP $c: conflict in: $files (resolve, git add, re-run)"; break; }
      resolve_keep_ubuntu $files
      log "CONFLICT $c $files -> kept Ubuntu hunks (policy, unverified)"
    fi
    finish "$c" || break
  done
}

# Remember every stack commit that did not land (dropped by git as empty, or skipped above).
# Only meaningful when the replay ran (STATE/list exists) and nothing is pending.
remember_unlanded() {
  pick_pending >/dev/null && return 0
  [ -f "$STATE/list" ] || return 0
  landed > "$STATE/landed"
  grep -vxFf "$STATE/landed" "$STATE/list" >> "$SKIPFILE" || true
  sort -u -o "$SKIPFILE" "$SKIPFILE"
}

# --- marker ------------------------------------------------------------------------------
# Record the port in $MARKER_FILE, e.g.
#   Ubuntu-7.2.0-5.5 + v7.2.14 stable = asahi-7.2.14-1 (2026-10-31)
# "+ vX.Y.Z stable" appears when LINUX_TAG's SUBLEVEL differs from the Ubuntu base tag's.
add_marker() {
  local f=$MARKER_FILE sub ubu lsl tsl stable line
  [ -f "$f" ] || { log "marker: $f absent: BASE has no debian.asahi-arm packaging (wrong BASE?)"; return 0; }
  if git log --format=%s "$BASE..HEAD" | grep -qxF "Asahi patchset $ASAHI_TAG"; then
    log "marker: already present"; return 0
  fi
  sub=$(git log --first-parent -1 --format=%s --grep='^UBUNTU: Ubuntu-[0-9]' "$BASE")
  [ -n "$sub" ] || { log "marker: no 'UBUNTU: Ubuntu-X' commit below BASE; not added"; return 1; }
  ubu=${sub#UBUNTU: }
  lsl=$(git show "$LINUX_TAG:Makefile" | makefile_version | cut -d. -f3)
  tsl=$(git show "refs/tags/$ubu:Makefile" 2>/dev/null | makefile_version | cut -d. -f3)
  stable=""; [ "$tsl" = "$lsl" ] || stable=" + $LINUX_TAG stable"
  line=$(printf '\t%s%s = %s (%s)' "$ubu" "$stable" "$ASAHI_TAG" "${DATE:-$(date +%F)}")
  # Replace the first entry under [ubuntu-asahi]; append if the section has none.
  awk -v l="$line" 'f && /^\t/ {print l; f=0; next} /^\[ubuntu-asahi\]/ {f=1} {print}' "$f" > "$f.new" &&
    mv "$f.new" "$f"
  grep -qxF "$line" "$f" || printf '%s\n' "$line" >> "$f"
  git add "$f" && git commit -q -s -m "Asahi patchset $ASAHI_TAG" && log "marker:$line"
}

# --- report ------------------------------------------------------------------------------
# Merges are not replayed (--no-merges). List those whose resolution changed files beyond their
# parents ("evil" hunks); a human must carry these over (see: git diff-tree --cc -p <merge>).
report() {
  local m f
  log "merges with resolution-only changes (review, not applied):"
  for m in $(git rev-list --merges "$LINUX_TAG..$ASAHI_TAG"); do
    f=$(git diff-tree --cc -r --name-only --no-commit-id "$m" | tr '\n' ' ')
    [ -z "$f" ] || log "  $(git log -1 --format='%h %s' "$m" | cut -c1-80): $f"
  done
  git status -sb | head -3
  echo "applied: $(git rev-list --count "$BASE..HEAD") commits; log: $LOG"
  note_fedora "$ASAHI_TAG" .
}

main() {
  install_msgfix
  setup_worktree
  pick_pending >/dev/null || replay_stack
  resolve_loop
  remember_unlanded
  pick_pending >/dev/null || add_marker || log "STOP: marker not added"
  report
}
main
