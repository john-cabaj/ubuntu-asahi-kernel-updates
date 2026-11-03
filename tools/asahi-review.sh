#!/bin/bash
# List backports whose conflict resolution was made by asahi-port.sh and not yet reviewed, and
# commits marked as having no Asahi source (NO_ASAHI_NOTE in lib.sh).
#
# Such commits carry the unreviewed note (lib.sh) under "(backported from commit ...)". A human
# reviews each one, then replaces the note with "[their name: what was changed and why]".
#
# Usage: [REPO=dir] asahi-review.sh [--check] [RANGE]     (default RANGE: @{upstream}..HEAD)
#   --check   exit 1 if any unreviewed backport or no-Asahi-source commit remains
# For each commit prints: hash, subject, the Asahi source commit and the command that shows how
# the backport differs from the original patch.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check=0; [ "${1:-}" = --check ] && { check=1; shift; }
R=${REPO:-.}; range=${1:-@\{upstream\}..HEAD}

# Commits in RANGE whose message contains the fixed text $1.
commits_with() { git -C "$R" log --format=%H --fixed-strings --grep="$1" "$range"; }
# "<short hash> <subject>" of commit $1, cut to a readable width.
headline() { git -C "$R" log -1 --format='%h %s' "$1" | cut -c1-90; }

n=0
while read -r c; do
  src=$(git -C "$R" log -1 --format=%B "$c" | trailer_shas | head -1)
  headline "$c"
  echo "    source $src; review: git range-diff ${src:0:12}^! ${c:0:12}^!"
  n=$((n + 1))
done < <(commits_with "$UNREVIEWED_NOTE")
echo "$n unreviewed backport(s) in $range"

m=0
while read -r c; do
  headline "$c"
  git -C "$R" log -1 --format=%B "$c" | grep -F "$NO_ASAHI_NOTE" | sed 's/^/    /'
  m=$((m + 1))
done < <(commits_with "$NO_ASAHI_NOTE")
echo "$m commit(s) with no Asahi source in $range"

# With --check, any marked commit is a failure (e.g. before publishing).
[ "$check" = 0 ] || [ $((n + m)) = 0 ]
