---
name: asahi-port
description: Use when porting the Asahi Linux patch stack onto an Ubuntu Asahi tree (AGENTS.md case 1/2) or resolving cherry-pick conflicts during such a port. Wraps tools/asahi-port.sh.
---

# Asahi port

Run `asahi-release-check` first. Never push; never pass the Asahi base (AGENTS.md).

## Choosing BASE
BASE is the Ubuntu commit just before the Asahi stack, on the *target* kernel base
(e.g. an Ubuntu generic `UBUNTU: Ubuntu-7.2.0-5.5` commit at 7.2.12), not the tip of
an older-base Asahi branch. Check `Makefile` VERSION/PATCHLEVEL of BASE.

## Running
```sh
export GIT_AUTHOR_NAME=.. GIT_AUTHOR_EMAIL=.. GIT_COMMITTER_NAME=.. GIT_COMMITTER_EMAIL=..
UBUNTU_REPO=.. BASE=.. LINUX_TAG=v7.2.12 ASAHI_TAG=asahi-7.2.12-2 WORKTREE=/tmp/x BRANCH=asahi-port \
  tools/asahi-port.sh
```
It stops at each conflict. Resolve (`tools/conflict-side.py ours|theirs|both FILE`
for whole-file side picks, or edit), `git add`, re-run. It never loops: an empty
resolved pick is skipped; a pick that cannot finish prints `STOP`.

## Resolving conflicts
- Understand the change from the commit message and diff; the resolution has no
  independent check, so record why for each one.
- Keeping Ubuntu's side is right only if Ubuntu already has the equivalent change.
  Check whether incoming comments/docs still apply to the new code before dropping them.
- If incoming context has something Ubuntu lacks (e.g. a `+ 'static` bound), find where
  it came from (`git log -S`, then merges) before deciding.
- Merges are not replayed (`--no-merges`); handle their changes with `asahi-merge-review`.

## rerere
Enabled (`rerere.autoUpdate`); cache in `$UBUNTU_REPO/.git/rr-cache`. A recorded
resolution is replayed silently, so a wrong one propagates. If one is wrong, delete its
`rr-cache/<id>` dir and re-resolve. A fresh worktree should then run with no STOPs.

## Before calling it done
- Build arm64 with the asahi-arm config, Rust enabled; fix or report failures.
- Report what was not built or tested, the skipped (empty) picks, every conflict with
  its resolution, and the merges reviewed. Do not describe unbuilt results as verified.
