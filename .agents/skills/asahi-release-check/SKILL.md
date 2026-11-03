---
name: asahi-release-check
description: Use when asked whether a new Asahi Linux release is available, whether Ubuntu Asahi needs updating, or to check Asahi tags. Reports a new release only if a Fedora Asahi tag uses an Asahi Linux upstream tag more recent than the latest Asahi tag in Ubuntu Asahi's debian.asahi-arm/ubuntu-asahi.
---

# Asahi release check

Run `tools/asahi-release-check.sh`. It takes about 20 seconds and needs only `git ls-remote` and
`curl`, no clone. It prints `key=value` lines and a final `result=` line, and exits 1 with
`result=error: ...` on any failure. Report an error. Do not guess or use blog posts.

## What it does

The newest Asahi tag is the target. Fedora is informational (`AGENTS.md`).

1. Finds the newest AsahiLinux/linux tag (`asahi-X.Y.Z-N` only; ignore `v*` and `kernel-*`):
   `asahi_tag`.
2. Finds the newest Fedora Asahi tag, for comparison only. `ahead_of_fedora=yes` means
   `asahi_tag` is newer than it and at none of its commits. Say so in the report; it never
   blocks anything.
3. Finds the latest `Ubuntu-asahi-arm-*` tag, the branch `asahi-arm-X.Y`, and its Makefile
   X.Y.Z.
4. Compares the full versions numerically, never as strings:
   - Ubuntu lower than Asahi is **behind**: case 2, `tools/asahi-rebuild.sh`, stop before
     publishing.
   - Equal is **same**: case 1.
   - Ubuntu higher is **ahead**: case 3, clean cherry-picks only.
5. For same or ahead, compares `asahi_tag` with the latest tag in
   `debian.asahi-arm/ubuntu-asahi` (`latest_ported`). Not newer means no new release. Ubuntu may
   list tags newer than Fedora's; that is not an error.

## Report

Give the Fedora tag, Asahi tag, `ahead_of_fedora`, Ubuntu tag, versions, latest ported tag, and
the result. For a same-version new release, get the delta with `tools/asahi-delta.sh`.
