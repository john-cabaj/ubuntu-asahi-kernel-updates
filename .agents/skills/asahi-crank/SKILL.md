---
name: asahi-crank
description: Use after an Asahi port is complete (asahi-port, asahi-merge-review) to handle Asahi config changes and do the Ubuntu packaging for a same-release update (e.g. resolute to resolute) with cranky. Not for switching Ubuntu releases.
---

# Asahi crank

Packaging for a same-release update with cranky. Not for a switch to a
new Ubuntu release (that also needs "Moving to ..." packaging, variants, update.conf,
getabis); stop and report instead.

## Preconditions

- The port is done on a branch: Asahi commits, merge-review SAUCE commits, then the
  `Asahi patchset <tag>` marker (`debian.asahi-arm/ubuntu-asahi`) as the last commit.
- `cranky` and its chroot are available (`cranky chroot create-session RELEASE:linux`).
  If `cranky` is missing, stop and report; do not hand-edit the changelog.
- Set `GIT_AUTHOR_*`/`GIT_COMMITTER_*` in every call. Never push (AGENTS.md).

## Asahi config changes (before `cranky open`)

Fedora Asahi's configs are the source. They are one file per option under `redhat/configs/`,
on the Fedora branch only (the `asahi-*` tag commit has no `redhat/`). Fedora releases come
in pairs: `kernel-X.Y.Z-0` (plain ARK) and `kernel-X.Y.Z-N.asahi` (ARK plus the Asahi config
commits); the options that differ are the Asahi layer (45 options for 7.2.12). Ubuntu mirrors it by
hand in `debian.asahi-arm/config/annotations`, "Asahi enablement config" section, as
```text
CONFIG_X                                        policy<{'arm64': 'm'}>
CONFIG_X                                        note<'{Asahi enablement config}'>
```
(`y`/`m`, `n` for "is not set", numbers and strings as `'123'`/`'""'`; one `'arm64'` key covers
both flavours). Only annotations matter here, not a generated `.config`.
```sh
git ls-remote --tags https://gitlab.com/fedora-asahi/kernel-asahi.git 'kernel-*.asahi' | sort -V | tail -1   # release
git clone --depth 400 --filter=blob:none --no-checkout --branch fedora-asahi-X.Y \
  https://gitlab.com/fedora-asahi/kernel-asahi.git /tmp/fed
git -C /tmp/fed fetch --depth 400 origin tag kernel-X.Y.Z-0 tag kernel-X.Y.Z-N.asahi
tools/asahi-config-check.py --fedora /tmp/fed --repo <ubuntu tree> --ubuntu HEAD
```
Run it with the Asahi stack already on top of the tree (the normal order): the drivers, and
so the Kconfig symbols, arrive with the stack. It warns if most options are missing from the
tree. The release defaults to the newest `.asahi` tag in the clone (it contains the Fedora
ceiling tag). Statuses:
- `add` (Fedora y/m, Ubuntu has no policy): run again with `--apply --commit`. The commit
  `UBUNTU: [Config] asahi-arm: Enable Asahi options from Fedora <release>` goes ABOVE the Asahi
  stack, after any SAUCE and before the marker, which stays last (a later rebuild moves it
  below the next stack with the rest of the finished release). `asahi-rebuild.sh` does this
  itself when `FEDORA_CLONE=/tmp/fed` is set.
- `differs`, `review`: do not change; report Fedora's and Ubuntu's values for the user.
  A different policy can be deliberate (e.g. `DRM_NOVA`: Fedora `n`, Ubuntu `m`);
  `review` is a Fedora distro choice (disable, string, number), not copied.
- `notree`: the symbol is not in the tree being ported (Fedora's Asahi snapshot differs); skip.
- `removed`: no longer set in Fedora's release; report.
`--apply-updates` overwrites `differs` only if the user decides to take Fedora's value.
Nothing to do when there are no `add` rows.

## Steps

Run from the kernel tree, in this order:
1. `cranky open`: "UBUNTU: Start new release", an UNRELEASED changelog entry with the
   bumped version.
2. `cranky review-master-changes`: list `debian.master` changes (especially `rules.d`)
   and decide whether the derivative needs them. Report each; ask if unclear.
3. `cranky fdr clean updateconfigs`: if `config/annotations` changes, commit as
   `UBUNTU: [Config] asahi-arm: updateconfigs from vX.Y.Z`. No change, no commit.
4. `cranky close`: fills the changelog, sets series and date, updates `reconstruct`,
   and commits `UBUNTU: Ubuntu-asahi-arm-X.Y.0-ABI.N`. If it exits early on
   dependency config changes, commit those (reference the original bug) and re-run.
   Add no commits after `close` without re-running it.

Expected commit order on the branch (as in 7.0.0-1002.2 and 7.2.0-1001.1), bottom to top:
marker, Start new release, [Config] updateconfigs (optional), closing commit.

## Not in this skill

`cranky link-tb` (makes public changes), `test-build`, `update-dependents`, `tags`,
`build-sources`, `push-refs`, `dput-sources`: leave to the user. `update-dkms-versions`
is not needed (no `dkms-versions` file in debian.asahi-arm).

## Report

Version and ABI from the changelog, the commits added, any master changes reviewed, and
anything not run. Do not describe an unbuilt kernel as tested.
