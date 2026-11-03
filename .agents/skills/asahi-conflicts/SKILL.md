---
name: asahi-conflicts
description: Use when tools/asahi-port.sh or tools/asahi-rebuild.sh prints STOP on a cherry-pick conflict, or when resolving conflicts or rerere entries during an Asahi port.
---

# Asahi conflicts

Only needed when a replay stops. A clean run never loads this.

## Resolving a stop

The script prints `STOP <sha>: conflict in: <files>`.

1. Resolve the files: `tools/conflict-side.py ours|theirs|both FILE` for whole-file side picks,
   or edit by hand.
2. `git add` them.
3. Re-run the same command with the same env.

The script never loops. An empty resolved pick is skipped and remembered, and a pick that
cannot finish prints `STOP`.

Guidance for the resolution itself:

- Understand the change from the commit message and diff. Nothing independently checks a
  resolution, so record why for each one.
- Keep Ubuntu's side only if Ubuntu already has the equivalent change. First check what the
  incoming patch adds there (comments, docs, small changes) that still applies. Keep that and
  drop only what Ubuntu already has. A pick that ends up empty is skipped, so dropping
  everything silently loses the patch's addition (7.2.14: a two-line comment in
  `nova-core/fsp.rs`).
- If the incoming context has something Ubuntu lacks (for example a `+ 'static` bound), find
  where it came from (`git log -S`, then merges) before deciding.
- Merges are not replayed (`--no-merges`). Handle their changes with `asahi-merge-review`.
- If a resolution is not obvious, ask the user. Do not guess.

A resolved pick becomes "backported from commit" with the note
`[asahi-port: conflict resolved automatically, unreviewed]`. The script adds this, and rerere
replays get it too. The note names no person, because nobody has reviewed it yet.

## rerere

rerere is enabled (`rerere.autoUpdate`), with its cache in `$UBUNTU_REPO/.git/rr-cache`. A
recorded resolution is replayed silently, so a wrong one propagates. If one is wrong, delete
its `rr-cache/<id>` directory and re-resolve. A fresh run should then have no STOPs.

The cache lives in the Ubuntu repo's `.git`, so it goes with that repo. Do not delete, replace
or re-clone `UBUNTU_REPO` without copying `.git/rr-cache` first. Losing it loses every earlier
hand resolution, and a redo can then resolve differently (7.2.14: two conflicts did).

## Review afterwards

`tools/asahi-review.sh [--check] [RANGE]` lists the commits still carrying the unreviewed note,
each with the `git range-diff` command that shows how it differs from the Asahi original.
`--check` exits 1 if any remain.

A human reviews each one, then replaces the note with `[their name: what was changed and why]`,
or tags the commit their own way. That sign-off is the user's, per commit:

- Never write a person's name for them (`NOTE_NAME` is only for work that person has reviewed).
- Never sign off yourself.
- Do not stop a port to ask for review. Finish it, then report the list.

## Report

State plainly that some commits did not cherry-pick cleanly and were backported, and that they
need the user's review. List each one (hash, subject, file, resolution, why) from
`asahi-review.sh`.
