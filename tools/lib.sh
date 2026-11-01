# Shared helpers for tools/asahi-*.sh. Source it; do not execute.

# Where Ubuntu records ported Asahi releases (override for another flavour).
MARKER_FILE=${MARKER_FILE:-debian.asahi-arm/ubuntu-asahi}
# File names (ERE) that are Ubuntu packaging, not kernel source: a commit touching only
# these is part of the packaging layer rather than an Asahi/SAUCE source change.
PKG_PATHS=${PKG_PATHS:-^(debian|ubuntu/|Ubuntu\.md)}

# Note line asahi-port.sh adds under "(backported from commit ...)" when it resolved a conflict
# itself. Fixed text so tools/asahi-review.sh can find these commits later. A reviewer replaces
# it with their own "[name: what changed]" note; the tool never writes a person's name.
UNREVIEWED_NOTE='[asahi-port: conflict resolved automatically, unreviewed]'

# Linux tag an Asahi tag is based on: asahi-7.2.14-1 -> v7.2.14, asahi-6.4-10 -> v6.4.
linux_base_tag() { sed -E 's/^asahi-([0-9]+(\.[0-9]+)+)-[0-9]+$/v\1/' <<<"$1"; }

# X.Y.Z from Makefile text on stdin. Stops collecting at EXTRAVERSION but still reads all
# input, so a writer such as curl does not die of SIGPIPE.
makefile_version() {
  awk '/^EXTRAVERSION/{d=1} !d && /^(VERSION|PATCHLEVEL|SUBLEVEL) =/{v=v (v?".":"") $3} END{print v}'
}

# Source commit ids named by "(cherry picked|backported) from commit <sha>" lines in text on stdin.
trailer_shas() {
  grep -oE '(cherry picked|backported) from commit [0-9a-f]{40}' | awk '{print $NF}'
}

# True if version $1 is strictly newer than $2 (numeric, `sort -V`; never compare as strings).
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

# Export git author/committer identity from the author of commit $2 in repo $1, unless the
# caller already set GIT_AUTHOR_NAME. The repo may have no identity configured.
default_identity() {
  [ -z "${GIT_AUTHOR_NAME:-}" ] || return 0
  local n e
  IFS='|' read -r n e < <(git -C "$1" log -1 --format='%an|%ae' "$2")
  export GIT_AUTHOR_NAME=$n GIT_AUTHOR_EMAIL=$e GIT_COMMITTER_NAME=$n GIT_COMMITTER_EMAIL=$e
}

# --- Fedora ceiling (AGENTS.md hard rule) ---------------------------------------------------
FEDORA_URL=${FEDORA_URL:-https://gitlab.com/fedora-asahi/kernel-asahi.git}

# "name commit" per release tag (asahi-X.Y.Z-N only) of remote $1, oldest first. Annotated tags
# list twice; the ^{} line holds the commit.
release_tags() {
  git ls-remote --tags "$1" 'refs/tags/asahi-*' |
    awk -F'\t' '{n=substr($2,11); sub(/\^\{\}$/,"",n); c[n]=$1} END{for(n in c) print n, c[n]}' |
    grep -E '^asahi-[0-9]+(\.[0-9]+)+-[0-9]+ ' | sort -k1,1V
}
# Comparable release number: asahi-7.2.14-1 -> 7.2.14.1.
release_num() { sed -E 's/^asahi-//; s/-/./' <<<"$1"; }

# Refuse (return 1) to port Asahi tag $1 if it is newer than the newest Fedora Asahi tag. A tag
# at the same commit as any Fedora tag is allowed whatever its name. Fails closed: if the Fedora
# tags cannot be read, the ceiling cannot be checked. $2: repo holding $1 (default: cwd).
check_ceiling() {
  local tag=$1 repo=${2:-.} fed newest commit
  fed=$(release_tags "$FEDORA_URL")
  newest=$(tail -1 <<<"$fed" | cut -d' ' -f1)
  [ -n "$newest" ] || { echo "STOP: cannot read Fedora Asahi tags; the Fedora ceiling cannot be checked" >&2; return 1; }
  commit=$(git -C "$repo" rev-parse -q --verify "$tag^{commit}") || { echo "STOP: $tag not found in $repo" >&2; return 1; }
  awk -v c="$commit" '$2==c{f=1} END{exit !f}' <<<"$fed" && return 0
  if version_gt "$(release_num "$tag")" "$(release_num "$newest")"; then
    echo "STOP: $tag is newer than the newest Fedora Asahi tag $newest (AGENTS.md: Fedora tags are the ceiling)" >&2
    return 1
  fi
}
