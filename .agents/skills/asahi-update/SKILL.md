---
name: asahi-update
description: Use as the entry point when asked to update Ubuntu Asahi to a new Asahi Linux release, or to work out what an update needs. Routes to the other asahi-* skills and tools in order, with the stop points.
---

# Asahi update

Rules are in AGENTS.md (Fedora ceiling, never pass the Asahi base, never push). The port
tools enforce the ceiling themselves and refuse a newer tag; do not look for a way round it. This is
the order of work; each step names the skill or tool that holds the detail.

1. **Check:** `tools/asahi-release-check.sh` (skill `asahi-release-check`). Act on `result=`:
   - `no new release`: report and stop.
   - `error`: report it; do not guess.
   - `behind` (Ubuntu X.Y.Z lower): case 2, step 3b.
   - `new release` (same version): case 1, step 3a.
   - `ahead`: case 3, clean cherry-picks only (AGENTS.md); report skipped patches.
2. **Set up:** work on a scratch branch/worktree of the Ubuntu Asahi tree (never the
   published branch). Set `GIT_AUTHOR_*`/`GIT_COMMITTER_*` in every shell call.
   If a needed tag is missing locally: `git fetch URL tag NAME`.
3. **Port** (skill `asahi-port`):
   - a. Same version: `REPO=.. tools/asahi-delta.sh OLD NEW`; report dropped patches for a
     decision; cherry-pick the new ones oldest first with `-x` and the URL; diff touched
     files against the tag; marker last.
   - b. Behind: `tools/asahi-rebuild.sh` (drops only the old stack, keeps the rest).
     On `STOP`, load `asahi-conflicts`, resolve, re-run.
4. **Merge review** (skill `asahi-merge-review`): regenerate per-version SAUCE fixups
   from the merges; start from the rebuild's `new-only:` files.
5. **Config and packaging** (skill `asahi-crank`): first `tools/asahi-config-check.py`
   against Fedora Asahi's configs (apply and commit the `add` entries; report `differs`/`review`
   for the user), then `cranky open`, `review-master-changes`,
   `fdr clean updateconfigs`, `close`. Needs `cranky`; if absent, stop and say so.
6. **Build/test:** arm64, asahi-arm config, Rust on (a dedicated build skill is not
   written yet). If not done, say so; never call an unbuilt tree verified.
7. **Report and stop:** versions, tags, commits added, skipped/dropped patches, conflicts
   and resolutions, merges reviewed, config options added or left for a decision, the unreviewed backports (`tools/asahi-review.sh
   RANGE`; state that these did not cherry-pick cleanly and need the user's review; the user
   signs them off per commit, you never do; do not stop the port to ask), what was not run. Publishing (`link-tb`, tags,
   `push-refs`, `dput-sources`) is the user's; never push.
