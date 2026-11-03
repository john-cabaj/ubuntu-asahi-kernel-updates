---
name: asahi-crank
description: Use after an Asahi port is complete (asahi-port, asahi-merge-review) to handle Asahi config changes and do the Ubuntu packaging for a same-release update (e.g. resolute to resolute) with cranky. Not for switching Ubuntu releases.
---

# Asahi crank

Packaging for a same-release update with cranky. A switch to a new Ubuntu release is out of
scope: it also needs "Moving to ..." packaging, variants, `update.conf` and getabis. Stop and
report instead.

## Before you start

- The port is finished on a branch: Asahi commits, merge-review SAUCE commits, then the
  `Asahi patchset <tag>` marker (`debian.asahi-arm/ubuntu-asahi`) as the last commit.
- Work in the supplied tree (the handle directory), never a separate worktree or clone.
- Use `local-cranky` for every cranky command (`KERNEL_SERIES_USE=local cranky` in
  non-interactive shells). If `cranky` is missing, stop and report. Never hand-edit the
  changelog.
- Set `DEBEMAIL` and `DEBFULLNAME`: `cranky open` stops unless `DEBEMAIL` ends in
  `@canonical.com`. In `~/.bashrc` they must sit above the interactive-shell guard, or
  non-interactive shells never see them.
- Set `GIT_AUTHOR_*` and `GIT_COMMITTER_*` in every call. Never push (AGENTS.md).
- Check the chroot (see "Chroot problems" if a check fails):
  ```sh
  schroot -l --all-sessions
  schroot -c session:cranky--stonking-amd64 -r -d / -- sh -c 'ls -l /dev/null; dpkg -l debhelper'
  ```
  `/dev/null` must be a character device (`c`) and `debhelper` must show `ii`. Use `schroot`
  for checks: `cranky chroot run -- cmd args` mishandles arguments.

## Asahi config changes (before `cranky open`)

Fedora Asahi's configs are the source. They are one file per option under `redhat/configs/`,
on the Fedora branch only (the `asahi-*` tag commit has no `redhat/`). Fedora releases come in
pairs:

- `kernel-X.Y.Z-0`: plain ARK.
- `kernel-X.Y.Z-N.asahi`: ARK plus the Asahi config commits.

The options that differ are the "Asahi layer" (45 options for 7.2.12). Ubuntu mirrors it by
hand in the "Asahi enablement config" section of `debian.asahi-arm/config/annotations`:

```text
CONFIG_X                                        policy<{'arm64': 'm'}>
CONFIG_X                                        note<'{Asahi enablement config}'>
```

Values are `y`/`m`, `n` for "is not set", and numbers and strings as `'123'`/`'""'`. One
`'arm64'` key covers both flavours. Only the annotations matter here, not a generated `.config`.

Get a cheap Fedora clone and run the check with the Asahi stack already on top of the tree
(its drivers bring the Kconfig symbols; the tool warns if most options are missing):

```sh
git ls-remote --tags https://gitlab.com/fedora-asahi/kernel-asahi.git 'kernel-*.asahi' | sort -V | tail -1
git clone --depth 400 --filter=blob:none --no-checkout --branch fedora-asahi-X.Y \
  https://gitlab.com/fedora-asahi/kernel-asahi.git /tmp/fed
git -C /tmp/fed fetch --depth 400 origin tag kernel-X.Y.Z-0 tag kernel-X.Y.Z-N.asahi
tools/asahi-config-check.py --fedora /tmp/fed --repo <ubuntu tree> --ubuntu HEAD
```

The release defaults to the newest `.asahi` tag in the clone. If the Asahi tag is ahead of
Fedora, the config comes from Fedora's latest release; say so. What to do per status:

| Status | Meaning | Action |
|--------|---------|--------|
| `add` | Fedora y/m, Ubuntu has no policy | Re-run with `--apply --commit` (see below). |
| `differs` | Ubuntu has another policy | Do not change. Report both values. It can be deliberate (`DRM_NOVA`: Fedora `n`, Ubuntu `m`). |
| `review` | Fedora distro choice (disable, string, number) | Do not copy. Report both values. |
| `notree` | The symbol is not in this tree | Skip. Fedora's Asahi snapshot differs. |
| `removed` | No longer set in Fedora's release | Report. |

The `add` commit is `UBUNTU: [Config] asahi-arm: Enable Asahi options from Fedora <release>`.
It goes above the Asahi stack, after any SAUCE and before the marker, which stays last.
`asahi-rebuild.sh` does this itself when `FEDORA_CLONE=/tmp/fed` is set. `--apply-updates`
overwrites `differs` rows only if the user decides to take Fedora's value. With no `add` rows
there is nothing to do.

## Steps

Run from the kernel tree, in this order.

1. **`cranky fix`**: syncs the in-tree helper scripts and `update.conf`, and commits if
   anything changed. Run it before every `cranky open`.

2. **`cranky rebase --dry-run`**, then decide. Rebase onto the master kernel only after the old
   Asahi patches have been dropped (`asahi-rebuild.sh` does that). Read the line
   `Rebase needed between X and Y`:
   - If Y's kernel base (X.Y) is above the Asahi tag's base, **do not rebase**. This is the
     AGENTS.md hard rule. `master-next` can be on a newer base: for 7.2.14 it reported
     `Ubuntu-7.3.0-10.10` against `7.2.0-5.5`. Report it.
   - Otherwise run `cranky rebase` (it fetches the master branch from `update.conf`, or use
     `-r REPO -b BRANCH`). Conflicts only in `debian/scripts` can be skipped with
     `git rebase --skip`; resolve the rest by hand. Then re-run `cranky fix`.

3. **`cranky open`**: makes "UBUNTU: Start new release" with an UNRELEASED changelog entry and
   the bumped version.

4. **`cranky review-master-changes`**: lists `debian.master` changes (especially `rules.d`).
   Decide whether the derivative needs them, report each, and ask if unclear. Run it before
   `close`, since it refuses a closed release. It fails with "Failed to retrieve base master
   version" because `debian.asahi-arm/changelog` has no `[ Ubuntu: X.Y.Z-N.M ]` line. In that
   case diff `debian.master` against the old branch instead: with the same generic base (the
   `UBUNTU: Ubuntu-X.Y.0-N.M` commit) there is nothing to review.

5. **`cranky fdr clean updateconfigs`**: if `config/annotations` changes, commit it as
   `UBUNTU: [Config] asahi-arm: updateconfigs from vX.Y.Z`. No change means no commit.

6. **`cranky close --base-version <generic base version>`** (for example `7.2.0-5.5`, from the
   `UBUNTU: Ubuntu-X.Y.0-N.M` base commit or `debian.master/changelog`; the user confirmed it
   for 7.2.0-1002.2). It fills the changelog, sets series and date, updates `reconstruct`, and
   commits `UBUNTU: Ubuntu-asahi-arm-X.Y.0-ABI.N`. If it exits early on dependency config
   changes, commit those (reference the original bug) and re-run it. Add no commits after
   `close` without re-running it.

Expected commit order on the branch (as in 7.0.0-1002.2 and 7.2.0-1001.1), bottom to top:
marker, Start new release, `[Config]` updateconfigs (optional), closing commit.

## Chroot problems

These came up in the sandbox container. A normal machine needs none of this.

- **`cannot create /dev/null: Permission denied`**: `mknod` is refused there, so the base chroot
  gets plain root-owned files in `dev/` and `debian/rules` fails. Workaround:
  1. Bind-mount host devices in `/etc/schroot/sbuild/fstab`:
     `/dev/null /dev/null none rw,bind 0 0`, and likewise `zero`, `random`, `urandom`.
  2. `touch` the same names in `<chroot>/dev/`.
  3. Destroy and recreate the session.

  Only `updateconfigs` and builds need this; `open` and `close` do not.
- **`dh_testdir: command not found`**: the base lacks debhelper. Run
  `cranky chroot destroy-session`, then `destroy-base` (if it stops on permissions:
  `sudo rm -rf /var/lib/schroot/chroots/<series>-amd64`), then `create-base` and
  `create-session`.

Ask before destroying a chroot, and report any such change to the user.

## Not in this skill

Leave these to the user: `cranky link-tb` (it makes public changes), `test-build`,
`update-dependents`, `tags`, `build-sources`, `push-refs`, `dput-sources`.
`update-dkms-versions` is not needed (there is no `dkms-versions` file in `debian.asahi-arm`).

## Report

Give the version and ABI from the changelog, the commits added, any master changes reviewed,
and anything not run. Do not describe an unbuilt kernel as tested.
