---
name: asahi-release-check
description: Use when asked whether a new Asahi Linux release is available, whether Ubuntu Asahi needs updating, or to check Asahi tags. Reports a new release only if a Fedora Asahi tag uses an Asahi Linux upstream tag more recent than the latest Asahi tag in Ubuntu Asahi's debian.asahi-arm/ubuntu-asahi.
---

# Asahi release check

Uses only `git ls-remote` and `curl`; no local clone or state is needed.
Do not use blog posts or progress reports.
Report an error instead of guessing if any step fails or returns nothing.

Compare versions numerically, never as strings: turn `asahi-7.2.11-1` into
`7.2.11.1` and compare with `sort -V`. Kernel base is the first two fields (X.Y).

```sh
F=https://gitlab.com/fedora-asahi/kernel-asahi.git
A=https://github.com/AsahiLinux/linux.git
U=https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm
```

## 1. Newest Fedora Asahi tag (the ceiling)

Only tags matching `^asahi-[0-9]+(\.[0-9]+)+-[0-9]+$` count. Ignore `v*` and
`kernel-*` tags. Annotated tags list twice; the `^{}` line holds the commit.

```sh
git ls-remote --tags $F 'refs/tags/asahi-*' |
  awk -F'\t' '{n=substr($2,11); sub(/\^\{\}$/,"",n); c[n]=$1} END{for(n in c) print n, c[n]}' |
  grep -E '^asahi-[0-9]+(\.[0-9]+)+-[0-9]+ ' | sort -k1,1V | tail -1
```

Output: `FEDORA_TAG FEDORA_COMMIT`. This is the newest Fedora tag.

## 2. Matching AsahiLinux/linux tag

Find the release tag at the same commit. If several, prefer one named the same
as `FEDORA_TAG`, else the first. No match: stop and report an error. Newer
AsahiLinux/linux tags published before Fedora are never candidates.

```sh
git ls-remote --tags $A 'refs/tags/asahi-*' | grep FEDORA_COMMIT
```

Output is e.g. `<commit> refs/tags/asahi-7.2.11-1^{}`. The result is `ASAHI_TAG`.
Its kernel base is `ASAHI_BASE`, e.g. `7.2`.

## 3. Latest Ubuntu Asahi tag and branch

Latest Ubuntu tag (highest `Ubuntu-asahi-arm-X.Y.Z-ABI.N`; ignore
`Ubuntu-apple-arm-*`):

```sh
git ls-remote --tags $U 'refs/tags/Ubuntu-asahi-arm-*' |
  awk '{print $2}' | sed 's#refs/tags/##;s/\^{}//' | sort -uV | tail -1
```

`UBUNTU_BASE` is X.Y from that tag, e.g. `Ubuntu-asahi-arm-7.2.0-1001.1` gives
`7.2`. The branch is `asahi-arm-UBUNTU_BASE` (confirm it exists with
`git ls-remote --heads $U asahi-arm-UBUNTU_BASE`).

## 4. Compare kernel bases first

- `UBUNTU_BASE` > `ASAHI_BASE`: **Ubuntu ahead. Forbidden. Stop and report both
  versions.** Never update (AGENTS.md hard rule).
- `UBUNTU_BASE` < `ASAHI_BASE`: **Ubuntu behind.** Needs packaging changes, not
  cherry-picks. Stop and report.
- Equal: continue.

## 5. Compare patch level (same base only)

Latest Asahi tag Ubuntu has ported, on the branch:

```sh
curl -fsSL "$U/plain/debian.asahi-arm/ubuntu-asahi?h=asahi-arm-UBUNTU_BASE" |
  grep -oE '= asahi-[0-9]+(\.[0-9]+)+-[0-9]+' | sed 's/^= //' | sort -V | tail -1
```

This is `LATEST_PORTED`. If none is found, treat it as none.

- `ASAHI_TAG` is not newer than `LATEST_PORTED`: **no new release.** Ubuntu may
  list tags newer than Fedora's; that is not an error.
- `ASAHI_TAG` is newer, or nothing is ported: **new release**, the same-base
  cherry-pick case.

## Report

Give: Fedora tag, Asahi tag, Ubuntu tag, bases, latest ported, and the
result (no new release / new release / stop: ahead / stop: behind / error).
