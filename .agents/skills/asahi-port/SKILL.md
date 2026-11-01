---
name: asahi-port
description: Use when porting the Asahi Linux patch stack onto an Ubuntu Asahi tree (AGENTS.md case 1/2). Wraps tools/asahi-delta.sh, asahi-rebuild.sh and asahi-port.sh. Conflicts are in asahi-conflicts.
---

# Asahi port

Run `asahi-release-check` first. Never push; never pass the Asahi base (AGENTS.md).

Same X.Y.Z (small delta): `REPO=<ubuntu-asahi> tools/asahi-delta.sh OLD_TAG NEW_TAG` prints
the new patches (oldest first) and the dropped ones (report those). Cherry-pick the new
ones with `-x` and the provenance URL, diff the touched files against the new tag, add the
marker last. A stable gap or new base: `tools/asahi-rebuild.sh` (below).

## Choosing BASE
BASE is the Ubuntu commit just before the Asahi stack (packaging included), on the
*target* kernel base: the packaging tip after the rebase described below, not the tip of
an older-base Asahi branch. Check `Makefile` VERSION/PATCHLEVEL of BASE.

Layers of an Ubuntu Asahi branch, bottom to top: Linux base + stable catchup (generic
Ubuntu `UBUNTU: Ubuntu-X.Y.0-N.M`), the `debian.asahi-arm` packaging commits, the Asahi
stack, Ubuntu's top commits (SAUCE, the Asahi config enablement commit), the marker last. The Asahi
stack goes above the packaging so the packaging shows the included commits properly.

For a stable gap or large rebase (e.g. 7.2.12 to 7.2.14), run `tools/asahi-rebuild.sh`. It
starts from the existing Ubuntu Asahi branch, drops only the old Asahi stack, and replays
the new one (as Asahi does):
```sh
UBUNTU_REPO=.. OLD=asahi-arm-7.2 LINUX_TAG=v7.2.14 ASAHI_TAG=asahi-7.2.14-1 \
  WORKTREE=/tmp/x BRANCH=asahi-7.2.14-update tools/asahi-rebuild.sh
```
It finds the layers itself, prints a few lines, and on a stop says what to resolve; fix,
`git add`, re-run with the same env (finished phases are skipped). What it does:
1. Finds the generic base (nearest first-parent `UBUNTU: Ubuntu-<digit>`), the old stack
   (first cherry-picked commit up to the commit before the first `UBUNTU:`/`Asahi patchset`
   above it; refuses merges or debian files inside it), and sorts the non-Asahi commits
   above the stack: packaging-only go below, ones editing other files (e.g. rust-io SAUCE)
   go on top.
2. Merges the stable tag into the generic base (`merge-tree` check first), rebases the
   packaging onto it, cherry-picks (no `-x`) the below commits: previous release commits and
   old `Asahi patchset` markers stay.
3. Replays the new stack with `asahi-port.sh` (BASE = that result; its marker step runs).
4. With `FEDORA_CLONE` set, the Asahi config enablement commit is added above the stack (before
   the marker). Per-version fixups that sat above the old stack and edit stack files (e.g. the rust-io
   merge-resolution SAUCE) are dropped by default and listed: they fix one patchset
   version. Regenerate them for the new tag with `asahi-merge-review` (the verify step's
   `new-only:` files show where). `KEEP_TOP=1` carries them instead.
5. Verifies: missing non-stack commits (by subject) and stack files differing from the
   Asahi tag, against the old branch's baseline; `new-only:` should be empty.
Tested on asahi-arm-7.2 to asahi-7.2.14-1 (~4 min): with `KEEP_TOP=1` the tree was
identical to the hand-built branch; by default `new-only:` listed `rust/kernel/drm/gem/shmem.rs`
(the rust-io fixup, 93 lines), which merge review must regenerate.
Conflicts in the replay need hand resolution (skill `asahi-conflicts`). A small same-version delta
needs none of this.

## Pitfalls seen
- Wrong BASE is the main failure. The generic tag (`Ubuntu-7.2.0-5.5`) can sit on a
  different SUBLEVEL than the tree; use the in-tree commit, and the packaging tip for
  `asahi-port.sh`. A missing `debian.asahi-arm/ubuntu-asahi` at BASE means BASE is wrong.
- Do not drop the previous release or old markers: only the old Asahi stack goes.
- Identity: env vars do not persist between shell calls; set them in every call and use
  the name/email of the last Ubuntu commit (`git log -1 --format='%an <%ae>'`).
- New Asahi tags may be missing locally: `git fetch URL tag NAME` (a tag glob refspec
  is rejected).
- Keep output small: `asahi-port.sh ... | grep -vE ' Merge ' | tail`, `git rebase ... |
  tail -1`; never print per-commit rebase progress or the 20+ merge list unless reviewing.
- `asahi-port.sh` remembers every pick that did not land (empty/skipped) in
  `<gitdir>/asahi-skipped`, so a re-run applies nothing and never re-conflicts on them.
- `asahi-port.sh` alone puts the marker directly on the stack; `asahi-rebuild.sh` handles
  any top commits (`KEEP_TOP=1`) and keeps the marker last.

## Running
```sh
export GIT_AUTHOR_NAME=.. GIT_AUTHOR_EMAIL=.. GIT_COMMITTER_NAME=.. GIT_COMMITTER_EMAIL=..
UBUNTU_REPO=.. BASE=.. LINUX_TAG=v7.2.12 ASAHI_TAG=asahi-7.2.12-2 WORKTREE=/tmp/x BRANCH=asahi-port \
  tools/asahi-port.sh
```
It stops at each conflict (`STOP`): load skill `asahi-conflicts`, resolve, `git add`, re-run.

## Marker (last step)
After the replay, the script commits `Asahi patchset $ASAHI_TAG`, updating
`debian.asahi-arm/ubuntu-asahi` to `<Ubuntu base tag> [+ vX.Y.Z stable] = <tag> (<date>)`.
The date is today (override with `DATE`); the base tag comes from the `UBUNTU: Ubuntu-X`
commit below BASE; `+ vX.Y.Z stable` appears when LINUX_TAG's SUBLEVEL differs from that
tag's. It is skipped if a pick is still pending, and if `debian.asahi-arm/ubuntu-asahi` is
absent (BASE has no packaging layer, which means BASE is wrong; see Layers).

## Verifying and the top layer
- Diff only the files in `LINUX_TAG..ASAHI_TAG` against the Asahi tag. Compare with the
  same diff for the previous port (old tree vs old tag): that is the baseline of expected
  differences (Ubuntu base code, newer upstream). Only new differences need attention.
- The replay carries Asahi commits only. Ubuntu's top commits (Moving to ...,
  config, SAUCE such as the rust-io merge-resolution commit) are layered afterwards;
  SAUCE commits fix one patchset version: regenerate them with merge review, do not carry
  the old ones (the earlier commit may serve as a starting point if the hunks are identical).
- Merge review: `git diff-tree --cc -p` shows only real resolution hunks; a merge listed by
  the script can have none. Files that already equal the Asahi tag need nothing.

## Before calling it done
- Build arm64 with the asahi-arm config, Rust enabled; fix or report failures.
- Run `tools/asahi-review.sh` on the new range and report the unreviewed backports.
- Report what was not built or tested, the skipped (empty) picks, every conflict with
  its resolution, and the merges reviewed. Do not describe unbuilt results as verified.
