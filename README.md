# Ubuntu Asahi Kernel Updates

This project will provide tooling to create Ubuntu kernel trees carrying the
upstream Asahi Linux patch set. Its first component detects Fedora Asahi
releases, which are the gate for considering an Ubuntu update.

## Project Layout

- `AGENTS.md`: hard rules and update cases for AI agents.
- `.agents/skills/asahi-release-check/SKILL.md`: a tool-neutral Agent Skill
  that checks for a new release using only `git` and `curl`. There are no
  scripts and no local state.

## Release Check

The Fedora Asahi tag is the ceiling. Only the AsahiLinux/linux tag matching the
newest Fedora tag (found by comparing commit ids) is considered; newer upstream
Asahi tags published before Fedora are never candidates.

The skill compares the kernel base (X.Y) of the latest Ubuntu Asahi tag with the
base of that gated Asahi tag (see `AGENTS.md`):

- Ubuntu base **behind**: stop. Needs packaging changes (case 3).
- Ubuntu base **ahead**: stop. Forbidden (case 2).
- **Same** base: a new release exists when the gated Asahi tag is more recent
  than the latest Asahi tag listed in `debian.asahi-arm/ubuntu-asahi` on the
  Ubuntu Asahi branch. Equal or older is not new.

Sources:

- Fedora Asahi: `https://gitlab.com/fedora-asahi/kernel-asahi.git`
- Asahi Linux: `https://github.com/AsahiLinux/linux.git`
- Ubuntu Asahi: `https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm`
