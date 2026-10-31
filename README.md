# Ubuntu Asahi Kernel Updates

This project will provide tooling to create Ubuntu kernel trees carrying the
upstream Asahi Linux patch set. Its first component detects Fedora Asahi
releases, which are the gate for considering an Ubuntu update.

## Project Layout

- `AGENTS.md`: hard rules and update cases for AI agents.
- `.agents/skills/asahi-release-check/SKILL.md`: a tool-neutral Agent Skill
  that checks for a new release using only `git` and `curl`. There are no
  scripts and no local state.

- `.agents/skills/asahi-port/SKILL.md`: workflow and rules for porting the stack.
- `.agents/skills/asahi-merge-review/SKILL.md`: carrying over merge-only changes.
- `tools/asahi-port.sh`: replays the Asahi stack with rerere, stall protection and
  merge-resolution reporting. `tools/conflict-side.py`: pick a side in conflict hunks.

## Release Check

The Fedora Asahi tag is the ceiling. Only the AsahiLinux/linux tag matching the
newest Fedora tag (found by comparing commit ids) is considered; newer upstream
Asahi tags published before Fedora are never candidates.

The skill compares the kernel version (X.Y.Z, including the stable level) of the
Ubuntu Asahi branch with that of the Asahi tag (see `AGENTS.md`):

- Ubuntu **behind** (base or only stable level): stop (case 2).
- Ubuntu **ahead**: only clean cherry-picks (case 3).
- **Same** version: a new release exists when the Asahi tag is more recent
  than the latest Asahi tag listed in `debian.asahi-arm/ubuntu-asahi` on the
  Ubuntu Asahi branch. Equal or older is not new (case 1).

Sources:

- Fedora Asahi: `https://gitlab.com/fedora-asahi/kernel-asahi.git`
- Asahi Linux: `https://github.com/AsahiLinux/linux.git`
- Ubuntu Asahi: `https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm`
