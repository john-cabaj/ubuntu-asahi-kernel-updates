---
name: asahi-update
description: Use as the entry point when asked to update Ubuntu Asahi to a new Asahi Linux release, or to work out what an update needs. Routes to the other asahi-* skills and tools in order, with the stop points.
---

# Asahi update

Rules are in AGENTS.md (target the latest Asahi tag, never pass the Asahi base, never
push). If the tag is ahead of Fedora Asahi (`ahead_of_fedora=yes`, also noted by the port
tools), say so in every report. This is the order of work; each step names the skill or tool that holds the detail.

1. **Check:** `tools/asahi-release-check.sh` (skill `asahi-release-check`). Act on `result=`:
   - `no new release`: report and stop.
   - `error`: report it; do not guess.
   - `behind` (Ubuntu X.Y.Z lower): case 2, step 3b.
   - `new release` (same version): case 1, step 3a.
   - `ahead`: case 3, clean cherry-picks only (AGENTS.md); report skipped patches.
2. **Set up:** work in the Ubuntu Asahi tree supplied in its handle directory
   (e.g. `.../linux-asahi-arm/linux-main`), on a new local branch (never the published
   branch). Do not create separate worktrees: cranky only accepts that directory. Pass it as
   both `UBUNTU_REPO` and `WORKTREE`. Set `GIT_AUTHOR_*`/`GIT_COMMITTER_*` and
   `DEBEMAIL`/`DEBFULLNAME` in every shell call. Run every cranky command as
   `local-cranky` (an alias in `~/.bashrc`, which aliases do not expand in non-interactive
   shells: use `KERNEL_SERIES_USE=local cranky`). Plain `cranky` does not work here.
   If a needed tag is missing locally: `git fetch URL tag NAME`.
   Optional backup (the old stack also stays in git on the old branch):
   `git format-patch -o ~/work/old-stack FIRST^..LAST` over the old Asahi commits.
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
7. **Report and stop:** report
   - versions and tags, whether the release is ahead of Fedora Asahi, commits added, skipped and dropped patches;
   - conflicts and their resolutions, merges reviewed;
   - config options added or left for a decision;
   - the unreviewed backports (`tools/asahi-review.sh RANGE`): say they did not
     cherry-pick cleanly and need the user's review. The user signs them off per commit,
     you never do, and you do not stop the port to ask;
   - what was not run.

   Publishing (`link-tb`, tags, `push-refs`, `dput-sources`) is the user's; never push.
