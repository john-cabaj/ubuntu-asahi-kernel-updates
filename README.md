# Ubuntu Asahi Kernel Updates

Tooling and agent guidance for building Ubuntu kernel trees that carry the upstream
Asahi Linux patch set. The newest Asahi Linux tag is always the target; releases ahead of
Fedora Asahi are flagged in reports.

Hard rules and the update cases live in [`AGENTS.md`](AGENTS.md); read it first.

## Workflow

Start with the `asahi-update` skill. It routes through the steps below in order:

1. **Check** for a new release (`asahi-release-check`).
2. **Port** the patch stack (`asahi-port`; `asahi-conflicts` only on a stop).
3. **Review merges** for changes that cherry-picking loses (`asahi-merge-review`).
4. **Config and packaging** with cranky (`asahi-crank`).

Nothing here pushes or publishes; that is always left to the user.

## Repo locations

The tools do not discover repositories; each location is passed in. There is no config file.

| What | Example | How it is passed |
|------|---------|------------------|
| Ubuntu Asahi tree (`linux-main`) | `~/canonical/kernel/ubuntu/stonking/linux-asahi-arm/linux-main` | `UBUNTU_REPO` (`asahi-port.sh`, `asahi-rebuild.sh`; required), `REPO` (`asahi-delta.sh`, `asahi-review.sh`; default `.`), `--repo` (`asahi-config-check.py`; default `.`) |
| Asahi Linux clone | `~/asahi` | Not passed. Fetch the tags the port needs into the Ubuntu tree first: `git fetch ~/asahi tag v7.2.14 tag asahi-7.2.14-1` (and the old release's tags for the verify step) |
| Fedora Asahi clone | `~/fedora-asahi` | `FEDORA_CLONE` (`asahi-rebuild.sh`, optional) or `--fedora` (`asahi-config-check.py`; required) |
| Worktree for the port | `~/work/asahi-7.2.14` | `WORKTREE` (required) |

Missing required variables stop the tool at once (`${VAR:?}`). `asahi-release-check.sh` needs
no local repos; it reads the public URLs (`ASAHI_URL`, `FEDORA_URL`, `UBUNTU_URL` override
them). Example:

```sh
UBUNTU_REPO=~/canonical/kernel/ubuntu/stonking/linux-asahi-arm/linux-main OLD=asahi-arm-7.2 \
  LINUX_TAG=v7.2.14 ASAHI_TAG=asahi-7.2.14-1 WORKTREE=~/work/asahi-7.2.14 \
  BRANCH=asahi-7.2.14-update FEDORA_CLONE=~/fedora-asahi tools/asahi-rebuild.sh
```

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
| `lib.sh`                | Shared helpers (sourced, not run): version compare, trailer parsing, identity, `MARKER_FILE`/`PKG_PATHS` defaults, ahead-of-Fedora note |
| `asahi-release-check.sh`| One-shot release report                                                  |
| `asahi-delta.sh`        | Patch-id delta (new/dropped) between two Asahi stacks                    |
| `asahi-rebuild.sh`      | Stable-gap or new-base rebuild: drop old stack, keep other commits, replay, add top commits and marker, verify |
| `asahi-port.sh`         | Replay the stack with rerere, stall protection and merge reporting       |
| `asahi-config-check.py` | Compare Fedora Asahi's config layer with Ubuntu's annotations; `--apply` writes missing entries |
| `asahi-review.sh`       | List backports whose conflict resolution a tool made and nobody reviewed |
| `conflict-side.py`      | Pick one side of every conflict hunk in a file                           |

`asahi-port.sh` and `asahi-rebuild.sh` print a note when the Asahi tag is ahead of the newest
Fedora Asahi tag. It is informational and never blocks a port.

## Release check

The candidate is the newest AsahiLinux/linux tag. Fedora Asahi is only a comparison: the
report says `ahead_of_fedora=yes` when the tag is newer than Fedora's newest and not at any
Fedora tag's commit.

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
