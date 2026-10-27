#!/usr/bin/env bash
# Tests for bin/asahi-tag-check using local git repos as the two remotes.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tool=$here/bin/asahi-tag-check
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fails=0

# mkrepo DIR [TAG:CONTENT ...]  - parentless, dated commits so the same CONTENT
# yields the same commit id in different repos.
export GIT_AUTHOR_DATE="2020-01-01T00:00:00Z" GIT_COMMITTER_DATE="2020-01-01T00:00:00Z"
mkrepo() {
    local dir=$1; shift
    git init -q "$dir"
    local spec tag content tree c
    for spec; do
        tag=${spec%%:*}; content=${spec#*:}
        tree=$(echo "$content" | git -C "$dir" hash-object -w --stdin)
        tree=$(printf '100644 blob %s\tf\n' "$tree" | git -C "$dir" mktree)
        c=$(git -C "$dir" commit-tree -m "$content" "$tree")
        git -C "$dir" tag "$tag" "$c"
    done
}

# run NAME STATE EXPECT_CODE EXPECT_OUT_SUBSTR [args]; remotes from $F and $A.
run() {
    local name=$1 state=$2 code=$3 want=$4; shift 4
    local sf=$work/state; rm -f "$sf"; [[ -n $state ]] && echo "$state" >"$sf"
    local out; out=$(FEDORA_URL=$F ASAHI_URL=$A "$tool" --state-file "$sf" "$@" 2>&1); local rc=$?
    if [[ $rc -ne $code || $out != *"$want"* ]]; then
        echo "FAIL $name: rc=$rc (want $code), out=[$out]"; fails=$((fails+1))
    else echo "ok   $name"; fi
    LAST_STATE=$(cat "$sf" 2>/dev/null)
}
expect_state() { [[ $LAST_STATE == "$1" ]] || { echo "FAIL state: [$LAST_STATE] want [$1]"; fails=$((fails+1)); }; }

# Fedora has non-release tags and numerically tricky versions (9 < 10).
F=$work/f; mkrepo "$F" kernel-7.2.12-400.asahi:a v7.2.12:b asahi-7.2.9-1:c asahi-7.2.10-1:d
A=$work/a; mkrepo "$A" asahi-7.2.9-1:c asahi-7.2.10-1:d

run baseline "" 0 "baseline: asahi-7.2.10-1"; expect_state asahi-7.2.10-1
run current asahi-7.2.10-1 0 "current: asahi-7.2.10-1"
run update asahi-7.2.9-1 10 "updated: asahi-7.2.9-1 -> asahi-7.2.10-1"; expect_state asahi-7.2.10-1
run reset asahi-7.2.9-1 0 "baseline: asahi-7.2.10-1" --reset
run older asahi-7.2.11-1 1 "older than stored"

# Same commit, different tag name upstream.
A2=$work/a2; mkrepo "$A2" asahi-7.2.10-2:d
A=$A2; run diffname asahi-7.2.9-1 10 "asahi-tag: asahi-7.2.10-2"

# Same name, different commit => unmatched, state not advanced.
A3=$work/a3; mkrepo "$A3" asahi-7.2.10-1:zzz
A=$A3; run unmatched asahi-7.2.9-1 1 "no matching tag"; expect_state asahi-7.2.9-1

# Annotated tag is matched by peeled commit.
F4=$work/f4; mkrepo "$F4" asahi-7.2.11-1:x; git -C "$F4" tag -a -f asahi-7.2.11-1 -m ann asahi-7.2.11-1^{commit}
A4=$work/a4; mkrepo "$A4" asahi-7.2.11-1:x
F=$F4 A=$A4 run annotated "" 0 "asahi-tag: asahi-7.2.11-1"

# No release tags / bad state / bad remote.
F5=$work/f5; mkrepo "$F5" v1:x; F=$F5 A=$A4 run norelease "" 1 "no asahi-X.Y.Z-N"
F=$F4 A=$A4 run badstate garbage 1 "invalid state file"
F=$work/missing A=$A4 run badremote "" 1 "could not list tags"

((fails)) && { echo "$fails failure(s)"; exit 1; }; echo "all passed"
