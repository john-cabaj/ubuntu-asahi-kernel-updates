---
name: asahi-port
description: Use when porting the Asahi Linux patch stack onto an Ubuntu Asahi tree (AGENTS.md case 1/2). Wraps tools/asahi-delta.sh, asahi-rebuild.sh and asahi-port.sh. Conflicts are in asahi-conflicts.
---

# Asahi port

Run `asahi-release-check` first. Never push, and never pass the Asahi kernel base (AGENTS.md).

## Choose the tool

| Situation | Tool |
|-----------|------|
| Same X.Y.Z, small delta (case 1) | `REPO=<ubuntu-asahi> tools/asahi-delta.sh OLD_TAG NEW_TAG` prints the new patches (oldest first) and the dropped ones. Report the dropped ones. Cherry-pick the new ones with `-x` and the Asahi URL, diff the touched files against the new tag, and add the marker last. |
| Stable gap or new base (case 2) | `tools/asahi-rebuild.sh` (below). |
| Replay onto a BASE you built yourself | `tools/asahi-port.sh` (below). |

The tools work in `UBUNTU_REPO` itself and switch it to the new branch, so it must be clean. There
is no separate worktree: cranky needs the handle directory. The port log is `asahi-port.log` in
the tree's git directory.

## Rebuild for a stable gap or new base

The rebuild starts from the existing Ubuntu Asahi branch, drops only the old Asahi stack, and
replays the new one the way Asahi does (about 4 minutes for 7.2.12 to 7.2.14):

```sh
UBUNTU_REPO=.. OLD=asahi-arm-7.2 LINUX_TAG=v7.2.14 ASAHI_TAG=asahi-7.2.14-1 \
  BRANCH=asahi-7.2.14-update tools/asahi-rebuild.sh
```

It finds the layers itself and prints a few lines. On a stop it says what to resolve: fix it,
`git add`, and re-run with the same env. Finished phases are skipped. What it does:

1. **Find the layers.** The generic base is the nearest first-parent `UBUNTU: Ubuntu-<digit>`
   commit. The old stack runs from the first cherry-picked commit to the commit before the first
   `UBUNTU:` or `Asahi patchset` commit above it (it refuses merges or `debian` files inside).
   Non-Asahi commits above the stack are sorted: packaging-only ones go below the new stack, ones
   that edit other files (such as the rust-io SAUCE) go on top.
2. **Build the new base.** On a branch `<BRANCH>-layers` in the tree, merges the stable tag into
   the generic base (after a `merge-tree` check), rebases the packaging onto it, and cherry-picks the "below" commits without `-x`.
   Previous release commits and old `Asahi patchset` markers stay.
3. **Replay the new stack** with `asahi-port.sh`. Its marker step runs.
4. **Top commits.** With `FEDORA_CLONE` set, the Asahi config enablement commit is added above
   the stack, before the marker. Per-version fixups that sat above the old stack and edit stack
   files (such as the rust-io merge-resolution SAUCE) are dropped by default and listed, because
   they fix one patchset version. Regenerate them with `asahi-merge-review`; the verify step's
   `new-only:` files show where. `KEEP_TOP=1` carries them instead.
5. **Verify.** Reports non-stack commits that went missing (by subject), and stack files that
   differ from the Asahi tag compared with the old branch's baseline. `new-only:` should be empty.

With `KEEP_TOP=1` the 7.2.14 tree was identical to the hand-built branch. By default `new-only:`
listed `rust/kernel/drm/gem/shmem.rs` (the rust-io fixup), which merge review must regenerate.

## Run `asahi-port.sh` directly

```sh
export GIT_AUTHOR_NAME=.. GIT_AUTHOR_EMAIL=.. GIT_COMMITTER_NAME=.. GIT_COMMITTER_EMAIL=..
UBUNTU_REPO=.. BASE=.. LINUX_TAG=v7.2.12 ASAHI_TAG=asahi-7.2.12-2 BRANCH=asahi-port \
  tools/asahi-port.sh
```

It stops at each conflict (`STOP`): load skill `asahi-conflicts`, resolve, `git add`, re-run.
Replay conflicts need hand resolution; a small same-version delta needs none of this.

### Choosing BASE

BASE is the Ubuntu commit just before the Asahi stack (packaging included), on the *target*
kernel base. That is the packaging tip after the rebase described above, not the tip of an
older-base Asahi branch. Check `VERSION`/`PATCHLEVEL` in BASE's `Makefile`. The branch layers
are described in `AGENTS.md`; a generic base commit has the subject `UBUNTU: Ubuntu-X.Y.0-N.M`.

### The marker (last step)

After the replay the script commits `Asahi patchset $ASAHI_TAG`, updating
`debian.asahi-arm/ubuntu-asahi` to `<Ubuntu base tag> [+ vX.Y.Z stable] = <tag> (<date>)`.

- The date is today (override with `DATE`).
- The base tag comes from the `UBUNTU: Ubuntu-X` commit below BASE.
- `+ vX.Y.Z stable` appears when LINUX_TAG's SUBLEVEL differs from that tag's.
- It is skipped if a pick is still pending, or if `debian.asahi-arm/ubuntu-asahi` is absent.
  An absent file means BASE has no packaging layer, so BASE is wrong.

`asahi-port.sh` alone puts the marker directly on the stack. `asahi-rebuild.sh` handles any top
commits and keeps the marker last.

## Provenance URL (required)

- Every Asahi commit needs `(cherry picked from commit <sha> https://github.com/AsahiLinux/linux)`,
  or `backported from` for a resolved conflict. `asahi-port.sh` adds the URL to its picks.
  Hand-made picks do not get it (`-x` alone gives no URL), so add it.
- A SAUCE commit built from a merge needs `(backported from merge commit <sha> <URL>)`.
- A change not sourced from Asahi has no commit to cite. Do not invent one. Add the line
  `[asahi-port: no Asahi source: <reason>]` (`NO_ASAHI_NOTE` in `tools/lib.sh`) to its message,
  the same way the unreviewed note is added to backports. `tools/asahi-review.sh` lists these,
  and you must report each in the final summary.

Check the whole stack before `cranky open`. Only the marker should be listed:

```sh
for c in $(git log --no-merges --format=%H LAYERS..STACK_TIP); do
  git log -1 --format=%B $c | grep -qE '^\((cherry picked|backported) from (merge )?commit [0-9a-f]+ https://' || echo $c
done
```

## Verifying the result

- Diff only the files in `LINUX_TAG..ASAHI_TAG` against the Asahi tag, and compare with the same
  diff for the previous port (old tree against old tag). That is the baseline of expected
  differences (Ubuntu base code, newer upstream). Only new differences need attention.
- The replay carries Asahi commits only. Ubuntu's top commits (Moving to ..., config, SAUCE such
  as the rust-io merge-resolution commit) are layered afterwards. SAUCE commits fix one patchset
  version: regenerate them with merge review rather than carrying the old ones. The earlier commit
  can serve as a starting point if the hunks are identical.
- For merge review, `git diff-tree --cc -p` shows only real resolution hunks. A merge the script
  lists can have none, and files that already equal the Asahi tag need nothing.

## Pitfalls seen

- **Wrong BASE is the main failure.** The generic tag (`Ubuntu-7.2.0-5.5`) can sit on a different
  SUBLEVEL than the tree. Use the in-tree commit, and the packaging tip for `asahi-port.sh`.
- Do not drop the previous release or old markers. Only the old Asahi stack goes.
- Environment variables do not persist between shell calls. Set the identity in every call, using
  the name and email of the last Ubuntu commit (`git log -1 --format='%an <%ae>'`).
- New Asahi tags may be missing locally: `git fetch URL tag NAME` (a tag glob refspec is rejected).
- Keep output small: `asahi-port.sh ... | grep -vE ' Merge ' | tail`, `git rebase ... | tail -1`.
  Do not print per-commit rebase progress or the 20+ merge list unless reviewing.
- `asahi-port.sh` remembers every pick that did not land (empty or skipped) in
  `<gitdir>/asahi-skipped`, so a re-run applies nothing and never re-conflicts on them.

## Before calling it done

- Build arm64 with the asahi-arm config and Rust enabled. Fix or report failures.
- Run `tools/asahi-review.sh` on the new range and report the unreviewed backports.
- Report what was not built or tested, the skipped (empty) picks, every conflict with its
  resolution, and the merges reviewed. Do not describe unbuilt results as verified.
