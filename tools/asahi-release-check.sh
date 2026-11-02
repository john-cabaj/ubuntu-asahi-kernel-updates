#!/bin/bash
# Is there a new Asahi Linux release for Ubuntu Asahi? (see the asahi-release-check skill)
#
# Needs only git ls-remote and curl. The candidate is the newest AsahiLinux/linux release tag.
# Fedora Asahi is informational: ahead_of_fedora=yes means the candidate is newer than the
# newest Fedora Asahi tag (and not at any Fedora tag's commit). Compares full X.Y.Z versions
# numerically.
#
# Prints key=value lines and a final "result=" line; exits 1 with "result=error: ..." on failure.
# Env (defaults are the public repos): FEDORA_URL ASAHI_URL UBUNTU_URL.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ASAHI_URL=${ASAHI_URL:-https://github.com/AsahiLinux/linux.git}
UBUNTU_URL=${UBUNTU_URL:-https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm}
err() { echo "result=error: $*"; exit 1; }

# Kernel version of a tag: asahi-7.2.14-1 -> 7.2.14, asahi-6.4-10 -> 6.4.0.
kernel_ver() {
  sed -E 's/^asahi-([0-9]+\.[0-9]+(\.[0-9]+)?)-.*/\1/' <<<"$1" | awk -F. '{print $1"."$2"."($3==""?0:$3)}'
}

# --- gather ------------------------------------------------------------------------------
asahi_tags=$(release_tags "$ASAHI_URL"); [ -n "$asahi_tags" ] || err "no Asahi tags"
ASAHI_TAG=$(tail -1 <<<"$asahi_tags" | cut -d' ' -f1)
ASAHI_COMMIT=$(tail -1 <<<"$asahi_tags" | cut -d' ' -f2)
fedora=$(release_tags "$FEDORA_URL" | tail -1)
FEDORA_TAG=${fedora% *}; FEDORA_COMMIT=${fedora#* }
# Ahead of Fedora: newer than Fedora's newest tag and not at any Fedora tag's commit.
if [ -z "$fedora" ]; then AHEAD=unknown
elif [ "$ASAHI_COMMIT" = "$FEDORA_COMMIT" ] || ! version_gt "$(release_num "$ASAHI_TAG")" "$(release_num "$FEDORA_TAG")"; then AHEAD=no
else AHEAD=yes; fi

UBUNTU_TAG=$(git ls-remote --tags "$UBUNTU_URL" 'refs/tags/Ubuntu-asahi-arm-*' |
  awk '{print $2}' | sed 's#refs/tags/##;s/\^{}//' | sort -uV | tail -1)
[ -n "$UBUNTU_TAG" ] || err "no Ubuntu Asahi tag"
UBASE=$(sed -E 's/^Ubuntu-asahi-arm-([0-9]+\.[0-9]+)\..*/\1/' <<<"$UBUNTU_TAG")
git ls-remote --heads "$UBUNTU_URL" "asahi-arm-$UBASE" | grep -q . || err "branch asahi-arm-$UBASE missing"
UBUNTU_VER=$(curl -fsSL "$UBUNTU_URL/plain/Makefile?h=asahi-arm-$UBASE" | makefile_version) || err "Makefile fetch"
[ -n "$UBUNTU_VER" ] || err "no Ubuntu version"
ASAHI_VER=$(kernel_ver "$ASAHI_TAG")
PORTED=$(curl -fsSL "$UBUNTU_URL/plain/$MARKER_FILE?h=asahi-arm-$UBASE" |
  grep -oE '= asahi-[0-9]+(\.[0-9]+)+-[0-9]+' | sed 's/^= //' | sort -V | tail -1)

# --- report ------------------------------------------------------------------------------
echo "fedora_tag=${FEDORA_TAG:-unknown}"; echo "asahi_tag=$ASAHI_TAG"; echo "ubuntu_tag=$UBUNTU_TAG"
echo "ahead_of_fedora=$AHEAD"
echo "ubuntu_version=$UBUNTU_VER asahi_version=$ASAHI_VER latest_ported=${PORTED:-none}"

# Is the Asahi tag newer than what Ubuntu has ported (or is nothing ported)?
newer_than_ported() { [ -z "$PORTED" ] || version_gt "$(release_num "$ASAHI_TAG")" "$(release_num "$PORTED")"; }

if [ "$UBUNTU_VER" = "$ASAHI_VER" ]; then
  newer_than_ported && echo "result=new release $ASAHI_TAG (case 1: asahi-delta.sh then cherry-pick)" || echo "result=no new release"
elif version_gt "$ASAHI_VER" "$UBUNTU_VER"; then
  echo "result=behind: Ubuntu $UBUNTU_VER < Asahi $ASAHI_VER (AGENTS.md case 2; asahi-rebuild.sh), stop before publishing"
else
  newer_than_ported && echo "result=ahead: Ubuntu $UBUNTU_VER > Asahi $ASAHI_VER; $ASAHI_TAG newer than ported; clean cherry-picks only (case 3)" || echo "result=no new release (Ubuntu ahead)"
fi
