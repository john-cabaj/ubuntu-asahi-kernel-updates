# AGENTS.md

Guidance for AI agents working in this repository. See `README.md` for the
tools and layout.

## Hard rules

### Never move the Ubuntu Asahi kernel base past the Asahi Linux kernel base

Updating the Ubuntu Asahi tree must never raise its kernel base (X.Y) above the
base of the Asahi Linux upstream tag being ported.

Always target the latest Asahi Linux upstream tag, even if it is newer than the newest
Fedora Asahi tag. When it is, say so (see "Ahead of Fedora" below).

- Never rebase, merge, or otherwise move the Ubuntu tree to a newer kernel base
  than the Asahi Linux tag's base.
- Never force-push or rewrite published history of the Ubuntu Asahi kernel tree (the Linux
  repo, e.g. `linux-main`). This does not apply to this project repo's own history.
- This rule is not to be worked around, overridden, or relaxed by an agent, even
  if a task seems to require it. Only the user may change it, by editing this file.

## Branch layers

Ubuntu Asahi branches are layered, bottom to top: Linux base + stable catchup (generic
Ubuntu tree), the `debian.asahi-arm` packaging commits (including earlier releases and
`Asahi patchset` markers), the Asahi port, then Ubuntu commits that edit stack files
(e.g. SAUCE), the Asahi config enablement commit, and the new marker last. The Asahi port goes on top of the packaging so the
packaging shows the included commits properly. Upstream Asahi only stacks its patches
on the Linux base; the packaging layering is Ubuntu's.

## Update cases

Compare the full kernel version (X.Y.Z, including the stable level) of the
Ubuntu Asahi tree with that of the new Asahi Linux tag, numerically:

1. **Same version (X.Y.Z):** cherry-pick the latest Asahi patches onto the Ubuntu tree.
   A small delta goes on top of the last Ubuntu Asahi release.
   - Find the delta by patch-id, not commit id (Asahi rebases): compare
     `git patch-id --stable` of `vX.Y.Z..old-tag` and `vX.Y.Z..new-tag`
     (non-merge). Check both new patches and patches dropped from the stack;
     a dropped patch cannot be cherry-picked, so report it for a decision.
   - Cherry-pick the new patches oldest first with `-x` and the provenance URL.
     Keep `fixup!` commits as separate commits, as Ubuntu already does.
   - Verify by diffing only the touched files against the new Asahi tag; the
     diff should be empty.
   - Add the `Asahi patchset <tag>` marker (`debian.asahi-arm/ubuntu-asahi`)
     last.
   - Set the git identity via `GIT_AUTHOR_*`/`GIT_COMMITTER_*` in every call.
2. **Ubuntu behind:** Ubuntu's X.Y.Z is lower than the tag's, whether the gap
   is a kernel base (X.Y) or only the stable level (Z). Bring Ubuntu Asahi up
   to the Asahi Linux version, then proceed as in case 1.
   - If a newer Ubuntu release contains a tree at the target base, start from
     that tree.
   - Otherwise, start from the existing Ubuntu Asahi branch. Merge the target
     stable tag into the generic Ubuntu base commit, rebase the packaging commits
     onto it (`git rebase --onto NEWBASE OLDBASE PKG_TIP`), and re-apply every
     other non-Asahi commit below the stack in order (previous releases and
     `Asahi patchset` markers included). Drop only the old Asahi stack (the
     contiguous range of cherry-picked Asahi commits), then replay the new
     stack on top with `tools/asahi-port.sh` (see the `asahi-port` skill). Ubuntu
     commits that edit stack files (e.g. SAUCE) go above the stack, then the
     new marker. Do not merge the stable tag on top of the old stack.
   - Never go past the Asahi Linux base (X.Y); a stable-only gap (same X.Y)
     is closed by moving the stable level forward, never past the tag's.
   - Stop and report before pushing or publishing anything.
   - Packaging for a same-release update (e.g. resolute to resolute) is the
     `asahi-crank` skill (`cranky open`, `review-master-changes`,
     `fdr clean updateconfigs`, `close`). [Open: a switch to a new Ubuntu release
     (extra packaging, variants, update.conf, getabis) is not yet specified.]
3. **Ubuntu ahead:** (higher X.Y.Z) the base stays as it is. Try to apply the latest Asahi
   Linux patchset, but accept only patches that resolve extremely easily.
   - Accept a patch only if `git cherry-pick` applies it cleanly, with no
     conflicts, no fuzz, and no manual edits.
   - Skip every other patch. Do not resolve conflicts or adapt patches.
   - Report all skipped patches and the reason for each.
   - Report both kernel versions.

## Ahead of Fedora

Fedora Asahi tags are informational, not a limit. If the Asahi tag being prepared is newer
than the newest Fedora Asahi tag (and not at the same commit as any Fedora tag), note it in
every report and in the final summary: the release is not yet in Fedora Asahi. The tools
print this as `ahead_of_fedora=yes`.
