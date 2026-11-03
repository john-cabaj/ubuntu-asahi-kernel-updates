# Ubuntu Asahi Kernel Updates

Tooling and agent guidance for building Ubuntu kernel trees that carry the upstream Asahi Linux
patch set. The newest Asahi Linux tag is always the target. Releases ahead of Fedora Asahi are
flagged in reports.

The hard rules and the update cases live in [`AGENTS.md`](AGENTS.md). Read it first.

## Workflow

Start with the `asahi-update` skill. It routes through these steps in order:

1. **Check** for a new release (`asahi-release-check`).
2. **Port** the patch stack (`asahi-port`; `asahi-conflicts` only on a stop).
3. **Review merges** for changes that cherry-picking loses (`asahi-merge-review`).
4. **Config and packaging** with cranky (`asahi-crank`).

Nothing here pushes or publishes. The user does that.

## Where things live

The tools do not discover repositories. Each location is passed in, and there is no config file.

| What | Example | How it is passed |
|------|---------|------------------|
| Ubuntu Asahi tree (`linux-main`) | `~/canonical/kernel/ubuntu/stonking/linux-asahi-arm/linux-main` | `UBUNTU_REPO` (required) for `asahi-port.sh` and `asahi-rebuild.sh`, which work in this tree itself (cranky needs that directory), so it must be clean; `REPO` (default `.`) for `asahi-delta.sh` and `asahi-review.sh`; `--repo` (default `.`) for `asahi-config-check.py` |
| Asahi Linux clone | `~/asahi` | Not passed. Fetch the tags first: `git fetch ~/asahi tag v7.2.14 tag asahi-7.2.14-1`, plus the old release's tags for the verify step |
| Fedora Asahi clone | `~/fedora-asahi` | `FEDORA_CLONE` (optional) for `asahi-rebuild.sh`; `--fedora` (required) for `asahi-config-check.py` |

Missing required variables stop a tool at once (`${VAR:?}`). `asahi-release-check.sh` needs no
local repos. It reads the public URLs, which `ASAHI_URL`, `FEDORA_URL` and `UBUNTU_URL` override.

Example rebuild:

```sh
UBUNTU_REPO=~/canonical/kernel/ubuntu/stonking/linux-asahi-arm/linux-main OLD=asahi-arm-7.2 \
  LINUX_TAG=v7.2.14 ASAHI_TAG=asahi-7.2.14-1 BRANCH=asahi-7.2.14-update \
  FEDORA_CLONE=~/fedora-asahi tools/asahi-rebuild.sh
```

## Skills

Skills live in `.agents/skills/<name>/SKILL.md` and are tool-neutral Agent Skills.

| Skill | Purpose |
|-------|---------|
| `asahi-update` | Entry point: order of work and stop points |
| `asahi-release-check` | Is there a new release? Needs only `git` and `curl` |
| `asahi-port` | Porting the stack onto an Ubuntu Asahi tree |
| `asahi-conflicts` | Resolving replay conflicts and rerere (loaded only on a STOP) |
| `asahi-merge-review` | Carrying over changes made inside upstream merge commits |
| `asahi-crank` | Config enablement and same-release packaging with cranky |

## Tools

Everything in `tools/`:

| Tool | Purpose |
|------|---------|
| `lib.sh` | Shared helpers, sourced and not run: version compare, trailer parsing, identity, the commit-message notes, the ahead-of-Fedora check |
| `asahi-release-check.sh` | One-shot release report |
| `asahi-delta.sh` | Patch-id delta (new and dropped) between two Asahi stacks |
| `asahi-rebuild.sh` | Stable-gap or new-base rebuild: drop the old stack, keep other commits, replay, add top commits and the marker, verify |
| `asahi-port.sh` | Replay the stack with rerere, stall protection and merge reporting |
| `asahi-config-check.py` | Compare Fedora Asahi's config layer with Ubuntu's annotations; `--apply` writes missing entries |
| `asahi-review.sh` | List backports nobody has reviewed, and commits with no Asahi source |
| `conflict-side.py` | Pick one side of every conflict hunk in a file |

`asahi-port.sh` and `asahi-rebuild.sh` print a note when the Asahi tag is ahead of the newest
Fedora Asahi tag. It is informational and never blocks a port.

## How the release check decides

The candidate is the newest AsahiLinux/linux tag. Fedora Asahi is only a comparison: the report
says `ahead_of_fedora=yes` when the tag is newer than Fedora's newest and not at any Fedora
tag's commit.

The full kernel version (X.Y.Z, including the stable level) of the Ubuntu Asahi branch is
compared numerically with the tag's (see `AGENTS.md`):

| Ubuntu vs. Asahi tag | Result |
|----------------------|--------|
| Behind | Stop. Case 2. |
| Ahead | Clean cherry-picks only. Case 3. |
| Same | New release if the tag is newer than the latest in `debian.asahi-arm/ubuntu-asahi`. Case 1. |

Sources:

- Fedora Asahi: <https://gitlab.com/fedora-asahi/kernel-asahi.git>
- Asahi Linux: <https://github.com/AsahiLinux/linux.git>
- Ubuntu Asahi: <https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm>
