#!/bin/bash
# Patch-id delta between two Asahi stacks (AGENTS.md case 1).
#
# Asahi rebases, so commit ids differ between tags; the same patch is recognised by
# `git patch-id --stable` over the non-merge commits of each tag's Linux base..tag range.
#
# Usage: [REPO=dir] asahi-delta.sh OLD_TAG NEW_TAG     (e.g. asahi-7.2.12-2 asahi-7.2.14-1)
# Prints a summary line, then:
#   NEW      in NEW_TAG only, oldest first (cherry-pick in this order)
#   DROPPED  in OLD_TAG only; cannot be cherry-picked, report for a decision
# REPO (default .) must contain both tags and their Linux base tags.
set -eu
[ $# = 2 ] || { echo "usage: $0 OLD_TAG NEW_TAG" >&2; exit 2; }
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
R=${REPO:-.}; old=$1; new=$2
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# "patch-id commit" lines for TAG's stack, oldest first.
stack_ids() {
  local base; base=$(linux_base_tag "$1")
  git -C "$R" rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "missing $base" >&2; exit 1; }
  git -C "$R" log --reverse --topo-order --no-merges -p --format='commit %H' "$base..$1" |
    git patch-id --stable
}
# Commits of file $2 whose patch-id is absent from file $1 (patch-ids are column 1).
only_in() { awk 'NR==FNR{seen[$1]=1; next} !($1 in seen){print $2}' "$1" "$2"; }
# Print "  <short> <subject>" for each commit id on stdin.
show() { while read -r c; do git -C "$R" log -1 --format='  %h %s' "$c"; done; }

stack_ids "$old" > "$T/old"; stack_ids "$new" > "$T/new"
only_in "$T/old" "$T/new" > "$T/n"
only_in "$T/new" "$T/old" > "$T/d"
echo "$old ($(wc -l < "$T/old")) -> $new ($(wc -l < "$T/new")): $(wc -l < "$T/n") new, $(wc -l < "$T/d") dropped"
echo "NEW:";     show < "$T/n"
echo "DROPPED:"; show < "$T/d"
