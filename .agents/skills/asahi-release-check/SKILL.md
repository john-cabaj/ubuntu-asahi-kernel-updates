---
name: asahi-release-check
description: Use when asked whether a new Asahi Linux release is available, whether Ubuntu Asahi needs updating, or to check Asahi tags. Reports a new release only if a Fedora Asahi tag uses an Asahi Linux upstream tag more recent than the latest Asahi tag in Ubuntu Asahi's debian.asahi-arm/ubuntu-asahi.
---

# Asahi release check

Run `tools/asahi-release-check.sh` (about 20 s; needs only `git ls-remote` and `curl`, no
clone). It prints `key=value` lines and a final `result=` line; it exits 1 with
`result=error: ...` on any failure. Report an error; do not guess or use blog posts.

What it does (Fedora tag is the ceiling, AGENTS.md):
1. Newest Fedora Asahi tag (`asahi-X.Y.Z-N` only; ignore `v*`, `kernel-*`).
2. The AsahiLinux/linux tag at the same commit (prefer the same name): `asahi_tag`. Newer
   upstream tags are printed as `newer_upstream_not_eligible`, never candidates.
3. Latest `Ubuntu-asahi-arm-*` tag, branch `asahi-arm-X.Y`, and its Makefile X.Y.Z.
4. Compares full versions numerically (never as strings): Ubuntu `<` Asahi is **behind**
   (case 2, `tools/asahi-rebuild.sh`, stop before publishing); `=` same (case 1); `>` ahead
   (case 3, clean cherry-picks only).
5. Same/ahead: compares `asahi_tag` with the latest tag in `debian.asahi-arm/ubuntu-asahi`
   (`latest_ported`); not newer means no new release. Ubuntu may list tags newer than
   Fedora's; that is not an error.

Report the printed fields: Fedora tag, Asahi tag, Ubuntu tag, versions, latest ported,
and the result. For a same-version new release, get the delta with `tools/asahi-delta.sh`.
