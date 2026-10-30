# AGENTS.md

Guidance for AI agents working in this repository. See `README.md` for the
tools and layout.

## Hard rules

### Never move the Ubuntu Asahi kernel base past the Asahi Linux kernel base

Updating the Ubuntu Asahi tree must never raise its kernel base (X.Y) above the
base of the Asahi Linux upstream tag being ported. Fedora Asahi tags are the
ceiling: never port an Asahi Linux tag newer than the newest Fedora Asahi tag.

- Never rebase, merge, or otherwise move the Ubuntu tree to a newer kernel base
  than the Asahi Linux tag's base.
- Never force-push or rewrite published history.
- This rule is not to be worked around, overridden, or relaxed by an agent, even
  if a task seems to require it. Only the user may change it, by editing this file.

## Update cases

Compare the kernel base (X.Y) of the Ubuntu Asahi tree with that of the new
Asahi Linux tag:

1. **Same base:** cherry-pick the latest Asahi patches onto the Ubuntu tree.
   This is the case currently being developed.
2. **Ubuntu behind:** bring Ubuntu Asahi up to the Asahi Linux base, then
   proceed as in case 1.
   - If a newer Ubuntu release contains a tree at the target base, start from
     that tree.
   - Otherwise, move the base forward on top of the current Ubuntu Asahi tree.
   - Never go past the Asahi Linux base.
   - Stop and report before pushing or publishing anything. [Open: approval
     and packaging details (debian.*, ABI, changelog) are not yet specified.]
3. **Ubuntu ahead:** the base stays as it is. Try to apply the latest Asahi
   Linux patchset, but accept only patches that resolve extremely easily.
   - Accept a patch only if `git cherry-pick` applies it cleanly, with no
     conflicts, no fuzz, and no manual edits.
   - Skip every other patch. Do not resolve conflicts or adapt patches.
   - Report all skipped patches and the reason for each.
   - Report both kernel versions.
