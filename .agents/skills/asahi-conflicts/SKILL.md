---
name: asahi-conflicts
description: Use when tools/asahi-port.sh or tools/asahi-rebuild.sh prints STOP on a cherry-pick conflict, or when resolving conflicts or rerere entries during an Asahi port.
---

# Asahi conflicts

Only needed when a replay stops. A clean run never loads this.

## Resolving
The script prints `STOP <sha>: conflict in: <files>`. Resolve (`tools/conflict-side.py
ours|theirs|both FILE` for whole-file side picks, or edit), `git add`, then re-run the
same command with the same env. It never loops: an empty resolved pick is skipped (and
remembered); a pick that cannot finish prints `STOP`.

- Understand the change from the commit message and diff; the resolution has no
  independent check, so record why for each one.
- Keeping Ubuntu's side is right only if Ubuntu already has the equivalent change.
  Check whether incoming comments/docs still apply to the new code before dropping them.
- If incoming context has something Ubuntu lacks (e.g. a `+ 'static` bound), find where
  it came from (`git log -S`, then merges) before deciding.
- Merges are not replayed (`--no-merges`); handle their changes with `asahi-merge-review`.
- A resolved pick becomes "backported from commit" with the note
  `[asahi-port: conflict resolved automatically, unreviewed]` (done by the script; rerere
  replays get it too). It names no person: nobody has reviewed it yet. If a resolution is
  not obvious, ask the user; do not guess.

## rerere
Enabled (`rerere.autoUpdate`); cache in `$UBUNTU_REPO/.git/rr-cache`. A recorded
resolution is replayed silently, so a wrong one propagates. If one is wrong, delete its
`rr-cache/<id>` dir and re-resolve. A fresh worktree should then run with no STOPs.

## Review afterwards
`tools/asahi-review.sh [--check] [RANGE]` lists the commits still carrying the unreviewed
note, each with the `git range-diff` command that shows how it differs from the Asahi
original (`--check` exits 1 if any remain). A human reviews each, then replaces the note
with `[their name: what was changed and why]`, or tags the commit their own way. That
sign-off is the user's, per commit. Never write a person's name for them (`NOTE_NAME` is for
work that person has reviewed), and never sign off yourself.
Do not stop a port to ask for review: finish it, then report the list (below).

## Report
State plainly that some commits did not cherry-pick cleanly and were backported, and need
the user's review. List each (hash, subject, file, resolution, why) from `asahi-review.sh`.
