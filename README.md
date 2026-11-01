# Ubuntu Asahi Kernel Updates

Tooling and agent guidance for building Ubuntu kernel trees that carry the upstream
Asahi Linux patch set. Fedora Asahi releases gate which Asahi tag may be considered.

Hard rules and the update cases live in [`AGENTS.md`](AGENTS.md); read it first.

## Workflow

Start with the `asahi-update` skill. It routes through the steps below in order:

1. **Check** for a new release (`asahi-release-check`).
2. **Port** the patch stack (`asahi-port`; `asahi-conflicts` only on a stop).
3. **Review merges** for changes that cherry-picking loses (`asahi-merge-review`).
4. **Config and packaging** with cranky (`asahi-crank`).

Nothing here pushes or publishes; that is always left to the user.

## Layout

### Skills (`.agents/skills/<name>/SKILL.md`)

Tool-neutral Agent Skills.

| Skill                 | Purpose                                                       |
|-----------------------|---------------------------------------------------------------|
| `asahi-update`        | Entry point: order of work and stop points                    |
| `asahi-release-check` | Is there a new release? Needs only `git` and `curl`           |
| `asahi-port`          | Porting the stack onto an Ubuntu Asahi tree                   |
| `asahi-conflicts`     | Resolving replay conflicts and rerere (loaded only on a STOP) |
| `asahi-merge-review`  | Carrying over changes made inside upstream merge commits      |
| `asahi-crank`         | Config enablement and same-release packaging with cranky      |

### Tools (`tools/`)

| Tool                    | Purpose                                                                  |
|-------------------------|--------------------------------------------------------------------------|
| `lib.sh`                | Shared helpers (sourced, not run): version compare, trailer parsing, identity, `MARKER_FILE`/`PKG_PATHS` defaults, `check_ceiling` |
| `asahi-release-check.sh`| One-shot release report                                                  |
| `asahi-delta.sh`        | Patch-id delta (new/dropped) between two Asahi stacks                    |
| `asahi-rebuild.sh`      | Stable-gap or new-base rebuild: drop old stack, keep other commits, replay, add top commits and marker, verify |
| `asahi-port.sh`         | Replay the stack with rerere, stall protection and merge reporting       |
| `asahi-config-check.py` | Compare Fedora Asahi's config layer with Ubuntu's annotations; `--apply` writes missing entries |
| `asahi-review.sh`       | List backports whose conflict resolution a tool made and nobody reviewed |
| `conflict-side.py`      | Pick one side of every conflict hunk in a file                           |

`asahi-port.sh` and `asahi-rebuild.sh` call `check_ceiling` first and refuse any Asahi tag
newer than the newest Fedora Asahi tag. It fails closed if Fedora is unreachable and has
no override.

## Release check

The Fedora Asahi tag is the ceiling. Only the AsahiLinux/linux tag at the commit of the
newest Fedora tag is a candidate; newer upstream tags are reported for information only.

The full kernel version (X.Y.Z, including the stable level) of the Ubuntu Asahi branch is
compared numerically with the tag's (see `AGENTS.md`):

| Ubuntu vs. Asahi tag | Result                                                                    |
|----------------------|---------------------------------------------------------------------------|
| Behind               | Stop; case 2                                                              |
| Ahead                | Clean cherry-picks only; case 3                                           |
| Same                 | New release if the tag is newer than the latest in `debian.asahi-arm/ubuntu-asahi`; case 1 |

Sources:

- Fedora Asahi: <https://gitlab.com/fedora-asahi/kernel-asahi.git>
- Asahi Linux: <https://github.com/AsahiLinux/linux.git>
- Ubuntu Asahi: <https://git.launchpad.net/~ubuntu-asahi/+git/linux-asahi-arm>
