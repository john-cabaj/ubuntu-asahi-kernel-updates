#!/bin/bash
# Port the Asahi Linux patchset onto an Ubuntu Asahi tree (AGENTS.md case 2/3 helper).
# Replays the whole Asahi stack, like Asahi does on a new Linux base, with the upstream
# URL added to each commit's provenance trailer in the same pass. Never pushes.
#
# Required env:
#   UBUNTU_REPO   path to the ubuntu-asahi clone (must already contain the Asahi tags/objects)
#   BASE          Ubuntu commit to start from (the commit just before the first Asahi patch)
#   LINUX_TAG     Linux tag the Asahi tag is based on (e.g. v7.2.12)
#   ASAHI_TAG     Asahi tag to port (e.g. asahi-7.2.12-2)
#   WORKTREE      where to create the scratch worktree
# Optional env:
#   BRANCH        new branch name (default: asahi-port)
#   KEEP_UBUNTU_FILES  space-separated files where, on conflict, Ubuntu's hunks are kept
#                 (opt-in policy; commits left empty by this are skipped). Unverified.
#   NOTE_NAME     name in the "[name: context changes]" backport note (default: john-cabaj)
#   URL           provenance URL (default: https://github.com/AsahiLinux/linux)
#   LOG           log file (default: $WORKTREE.conflicts.log)
#   GIT_AUTHOR_*/GIT_COMMITTER_*  identity (the repo may have none configured)
# Stops at each unresolved conflict. Resolve, `git add`, and re-run with the same env; an
# in-progress pick is detected and the stack is not replayed again.
set -u
: "${UBUNTU_REPO:?}" "${BASE:?}" "${LINUX_TAG:?}" "${ASAHI_TAG:?}" "${WORKTREE:?}"
BRANCH=${BRANCH:-asahi-port}; URL=${URL:-https://github.com/AsahiLinux/linux}
KEEP_UBUNTU_FILES=${KEEP_UBUNTU_FILES:-}
NOTE_NAME=${NOTE_NAME:-john-cabaj}
LOG=${LOG:-$WORKTREE.conflicts.log}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STATE=$(mktemp -d "${TMPDIR:-/tmp}/asahi-port.XXXXXX"); trap 'rm -rf "$STATE"' EXIT
export URL STATE NOTE_NAME

log() { echo "$*" | tee -a "$LOG"; }
# Mark the next commit as a conflict resolution (see the editor below).
mark_backport() { touch "$STATE/BACKPORT_ONCE"; }

# Editor used by cherry-pick -e. Adds the provenance URL to the (cherry picked|backported) line.
# If $STATE/BACKPORT_ONCE exists, the commit is a conflict resolution: relabel and annotate.
# One-shot on purpose: the editor setting persists across 'cherry-pick --continue'.
cat > "$STATE/msgfix" <<'EOS'
#!/bin/sh
f=$1
if [ -f "$STATE/BACKPORT_ONCE" ]; then
  rm -f "$STATE/BACKPORT_ONCE"
  sed -Ei 's#^\(cherry picked from commit#(backported from commit#' "$f"
  BP=1
fi
sed -Ei "s#^\((cherry picked|backported) from commit ([0-9a-f]+)\)\$#(\1 from commit \2 $URL)#" "$f"
[ -n "${BP:-}" ] && sed -Ei "/^\\(backported from commit/a [$NOTE_NAME: context changes]" "$f"
exit 0
EOS
chmod +x "$STATE/msgfix"
export GIT_EDITOR="$STATE/msgfix"

# --- setup -------------------------------------------------------------------------------
[ -d "$WORKTREE" ] || git -C "$UBUNTU_REPO" worktree add -q -b "$BRANCH" "$WORKTREE" "$BASE" || exit 1
cd "$WORKTREE" || exit 1
# rerere replays earlier hand resolutions (cache: $GIT_DIR/rr-cache); autoUpdate stages them.
git config rerere.enabled true; git config rerere.autoUpdate true
: > "$LOG"

# --- replay ------------------------------------------------------------------------------
pick_pending() { git rev-parse -q --verify CHERRY_PICK_HEAD; }

# Cherry-pick every Asahi commit not yet applied (matched by provenance trailer on resume).
replay_stack() {
  # Whole stack, linear, oldest first. --empty=drop skips patches already in the base.
  git rev-list --reverse --topo-order --no-merges "$LINUX_TAG..$ASAHI_TAG" > "$STATE/list" || exit 1
  git log --format=%B "$BASE..HEAD" |
    grep -oE '(cherry picked|backported) from commit [0-9a-f]{40}' | awk '{print $NF}' > "$STATE/done"
  grep -vxFf "$STATE/done" "$STATE/list" > "$STATE/todo" || true
  log "$(wc -l < "$STATE/list") Asahi commits, $(wc -l < "$STATE/todo") to apply"
  [ -s "$STATE/todo" ] && git cherry-pick -e -x -s --empty=drop $(cat "$STATE/todo") >> "$LOG" 2>&1
}

# Commit the staged resolution, or skip the pick if it became empty (the change is already in
# the tree). Returns 1 if the pick is still pending afterwards, so callers can never loop.
finish() {
  local c=$1
  git rerere >/dev/null 2>&1 || true            # record the resolution for later replay
  if git diff --cached --quiet; then
    log "  empty after resolution; skipped $c"
    git cherry-pick --skip >> "$LOG" 2>&1
  else
    mark_backport
    git cherry-pick --continue >> "$LOG" 2>&1
  fi
  [ "$(pick_pending)" != "$c" ] || { log "STOP $c: could not finish pick (see $LOG)"; return 1; }
}

# Keep Ubuntu's hunks in every conflicted file (policy, only for KEEP_UBUNTU_FILES).
resolve_keep_ubuntu() {
  for f in "$@"; do
    git checkout -q -m -- "$f"
    "$HERE/conflict-side.py" ours "$f" && git add "$f"
  done
}

# True if every given file is listed in KEEP_UBUNTU_FILES.
all_in_keep_list() {
  [ -n "$KEEP_UBUNTU_FILES" ] || return 1
  for f in "$@"; do case " $KEEP_UBUNTU_FILES " in *" $f "*) ;; *) return 1;; esac; done
}

unmerged() { git diff --name-only --diff-filter=U; }

pick_pending >/dev/null || replay_stack
stall=""
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

# --- report ------------------------------------------------------------------------------
# Merges are not replayed (--no-merges). List those whose resolution changed files beyond their
# parents ("evil" hunks); a human must carry these over (see: git diff-tree --cc -p <merge>).
log "merges with resolution-only changes (review, not applied):"
for m in $(git rev-list --merges "$LINUX_TAG..$ASAHI_TAG"); do
  f=$(git diff-tree --cc -r --name-only --no-commit-id "$m" | tr '\n' ' ')
  [ -z "$f" ] || log "  $(git log -1 --format='%h %s' "$m" | cut -c1-80): $f"
done
git status -sb | head -3
echo "applied: $(git rev-list --count "$BASE..HEAD") commits; log: $LOG"
