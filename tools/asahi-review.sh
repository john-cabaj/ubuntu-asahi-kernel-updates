#!/bin/bash
# List backports whose conflict resolution was made by asahi-port.sh and not yet reviewed.
#
# Such commits carry the unreviewed note (lib.sh) under "(backported from commit ...)". A human
# reviews each one, then replaces the note with "[their name: what was changed and why]".
#
# Usage: [REPO=dir] asahi-review.sh [--check] [RANGE]     (default RANGE: @{upstream}..HEAD)
#   --check   exit 1 if any unreviewed backport remains (e.g. before publishing)
# For each commit prints: hash, subject, the Asahi source commit and the command that shows how
# the backport differs from the original patch.
set -eu
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check=0; [ "${1:-}" = --check ] && { check=1; shift; }
R=${REPO:-.}; range=${1:-@\{upstream\}..HEAD}
n=0
while read -r c; do
  src=$(git -C "$R" log -1 --format=%B "$c" | trailer_shas | head -1)
  echo "$(git -C "$R" log -1 --format='%h %s' "$c" | cut -c1-90)"
  echo "    source $src; review: git range-diff ${src:0:12}^! ${c:0:12}^!"
  n=$((n + 1))
done < <(git -C "$R" log --format=%H --fixed-strings --grep="$UNREVIEWED_NOTE" "$range")
echo "$n unreviewed backport(s) in $range"
[ "$check" = 0 ] || [ "$n" = 0 ]
