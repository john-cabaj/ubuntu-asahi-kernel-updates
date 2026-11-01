---
name: asahi-merge-review
description: Use after tools/asahi-port.sh finishes, when it lists merges with resolution-only changes, or whenever Asahi merge commits may carry changes that cherry-picking non-merge commits loses.
---

# Asahi merge review

The Asahi tree is built from merges (`bits/*` into `asahi-wip`, upstream tags into
`drm-rust-next`). `asahi-port.sh` replays only non-merge commits, so changes made
inside a merge's conflict resolution ("evil" hunks) are lost. Examples seen: adding
`+ 'static` to `DeviceContext`/`DriverObject`, and converting `VMap` from `Io` to
`IoBase` after a rust-io merge.

## Procedure

1. Take the script's end-of-run list (or `git rev-list --merges LINUX_TAG..ASAHI_TAG`).
2. For each merge: `git diff-tree --cc -p <merge>` in the Asahi repo. Only lines that
   differ from every parent are evil hunks.
3. For each hunk, check the Ubuntu worktree:
   - Already present (the Ubuntu base or an applied pick supplies it): nothing to do.
   - Absent and needed by the code in the tree (the code would not build or would
     regress without it): carry it over.
   - Unclear: ask the user; do not guess.
4. Carry over as one SAUCE commit per merge:
   `UBUNTU: SAUCE: asahi-arm: Apply merge-resolution changes from <merge subject>`,
   body naming the merge and the files, trailer
   `(backported from merge commit <sha> <Asahi URL>)`.
5. Apply the hunks, not a whole file from the Asahi tag, unless the file differs only
   by those hunks (check with `diff`).

## Per-version

These SAUCE commits fix one patchset version and are not carried to the next port
(`asahi-rebuild.sh` drops them). Redo the review for each new tag; `asahi-rebuild.sh`'s
`new-only:` files are the starting point. An earlier commit can be a template if the
hunks are the same.

## Honesty

The merge commit is the only source for these hunks, so copying them is the method,
but it is not independent verification. Say so in the report, and list any merge you
reviewed but left unapplied, with the reason.
