---
name: asahi-update
description: Use as the entry point when asked to update Ubuntu Asahi to a new Asahi Linux release, or to work out what an update needs. Routes to the other asahi-* skills and tools in order, with the stop points.
---

# Asahi update

The hard rules are in `AGENTS.md`: target the latest Asahi tag, never pass the Asahi kernel
base, never push. If the tag is ahead of Fedora Asahi (`ahead_of_fedora=yes`, which the port
tools also print), say so in every report.

This skill gives the order of work. Each step names the skill or tool that holds the detail.

## 1. Check for a release

Run `tools/asahi-release-check.sh` (skill `asahi-release-check`) and act on `result=`:

| Result | Action |
|--------|--------|
| `no new release` | Report and stop. |
| `error` | Report it. Do not guess. |
| `new release` (same version) | AGENTS.md case 1: step 3a. |
| `behind` (Ubuntu X.Y.Z is lower) | AGENTS.md case 2: step 3b. |
| `ahead` | AGENTS.md case 3: clean cherry-picks only. Report skipped patches. |

## 2. Set up

- Work in the Ubuntu Asahi tree where it was supplied, in its handle directory (for example
  `.../linux-asahi-arm/linux-main`), on a new local branch. Never use the published branch and
  never create a separate worktree or clone: cranky only accepts the handle directory.
- Pass that tree as `UBUNTU_REPO`. The tools work in it directly and need it clean.
- Set `GIT_AUTHOR_*`, `GIT_COMMITTER_*`, `DEBEMAIL` and `DEBFULLNAME` in every shell call.
  Variables do not persist between calls.
- Run every cranky command as `local-cranky`. It is an alias for
  `KERNEL_SERIES_USE=local cranky`; aliases do not expand in non-interactive shells, so use
  the long form there. Plain `cranky` does not work in this setup.
- If a needed tag is missing locally: `git fetch URL tag NAME`.
- Optional backup of the old stack (it also stays in git on the old branch):
  `git format-patch -o ~/work/old-stack FIRST^..LAST` over the old Asahi commits.

## 3. Port (skill `asahi-port`)

- **a. Same version:** `REPO=.. tools/asahi-delta.sh OLD NEW`. Report the dropped patches for
  a decision. Cherry-pick the new ones oldest first with `-x` and the Asahi URL, diff the
  touched files against the tag, and add the marker last.
- **b. Behind:** `tools/asahi-rebuild.sh`. It drops only the old stack and keeps everything
  else. On `STOP`, load `asahi-conflicts`, resolve, and re-run.

## 4. Merge review and provenance

- **Merge review** (skill `asahi-merge-review`): regenerate the per-version SAUCE fixups from
  the merges, starting from the rebuild's `new-only:` files. A SAUCE commit built from a merge
  cites `(backported from merge commit <sha> <Asahi URL>)`, never a local sha.
- **Provenance check** (skill `asahi-port`, "Provenance URL"): every Asahi-sourced commit in
  the stack carries the Asahi URL. Only the marker may lack one. A change with no Asahi source
  gets the `[asahi-port: no Asahi source: <reason>]` note instead.

Fix both before packaging.

## 5. Config and packaging (skill `asahi-crank`)

Needs `cranky`. If it is missing, stop and say so. The skill gives the exact order:
config check, `cranky fix`, a `cranky rebase --dry-run` check, `open`, `review-master-changes`,
`updateconfigs`, `close`.

## 6. Report and stop

Report:

- Versions and tags, whether the release is ahead of Fedora Asahi, commits added, and skipped
  and dropped patches.
- Conflicts and their resolutions, and the merges reviewed.
- Config options added or left for a decision.
- The unreviewed backports (`tools/asahi-review.sh RANGE`). Say they did not cherry-pick
  cleanly and need the user's review. The user signs each one off. You never do, and you
  do not stop the port to ask.
- Commits with no Asahi source (`asahi-review.sh` lists them): hash, subject, reason.
- What was not run.

The user does any publishing. Never push.
