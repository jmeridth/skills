---
name: repo-reset
description: Pull latest main, switch to it, then assess and clean up merged branches and worktrees for a given repo
---

## Repo Reset

When invoked with a repo name (e.g., `/repo-reset mono`), perform the following steps in order:

### 1. Resolve the repo path

- Check common locations: `/Users/jason.meridth/code/<repo>`
- If the repo path doesn't exist, ask the user for the correct path

### 2. Fetch and update main

```bash
cd <repo-path>
git fetch upstream main 2>/dev/null || git fetch origin main
git checkout main
git merge upstream/main --ff-only 2>/dev/null || git merge origin/main --ff-only
```

- Prefer `upstream` remote if it exists, fall back to `origin`. Call the chosen remote `<remote>` below.
- If the merge fails (not fast-forward), STOP and tell the user - do not force reset

### 3. Verify every branch

Check each local branch except `main` (and `master`), including branches checked out in worktrees. Branch state drives both worktree and branch cleanup, so verify it once here.

- **Tip**: `git rev-parse <branch>`
- **Worktree**: from `git worktree list --porcelain`, the path that has the branch checked out, if any. The main worktree (the repo path itself, now on `main`) is never touched.
- **Dirty?**: `git -C <worktree-path> status --porcelain`. Non-empty output means uncommitted changes or untracked files.
- **Merged PR**: `gh pr list --head <branch> --state merged --json number,headRefOid,url`. A branch name alone does not prove anything. Someone else's fork, or an old PR from a reused branch name, can match. Pick the PR whose head matches the tip:
  - The tip equals `headRefOid`, or
  - The tip is an ancestor of `headRefOid`: `git fetch <remote> pull/<n>/head` then `git merge-base --is-ancestor <tip> FETCH_HEAD`. This covers a local branch that never pulled the PR's final commits.
- **Open PR**: `gh pr list --head <branch> --state open --json number --jq '.[0].number'`

Classify each branch:

- **Merged (fast-forward)**: the tip is an ancestor of `main` (`git merge-base --is-ancestor <tip> main`). `git branch -d` will accept it.
- **Merged (verified)**: not an ancestor of `main`, but a merged PR's head matches the tip as above. This is a squash or rebase merge. Deleting it needs `git branch -D`.
- **Skip (diverged)**: a merged PR exists for the branch name, but no merged PR's head matches the tip. The branch has commits that never merged.
- **Skip (open PR)**: the branch has an open PR.
- **Skip (no PR)**: no PR at all. This is likely local scratch work.

Then mark any merged branch whose worktree is dirty as **Skip (dirty)**. Uncommitted changes and untracked files are not in the PR.

Prunable worktrees (the `prunable` marker in `git worktree list --porcelain`) are tracked separately.

### 4. Confirm force-deletes (one prompt)

If any branch is **Merged (verified)**, list them all in one batch and ask once:

```
These branches were squash/rebase merged. Their tips match the merged PR heads, so nothing is lost.
Force-delete them, along with their clean worktrees?

  <branch>  <short-tip>  <PR url>  [worktree: <path>]
  ...

Force-delete N verified branches? [Y/n]
```

- End the turn and wait for the reply.
- Treat `y`, `yes`, `confirmed`, `proceed`, or an empty reply as yes. Treat anything else as no.
- On no, keep those branches and their worktrees, and report them as "skipped (force-delete declined)".
- Skip this step entirely if there are no **Merged (verified)** branches.

### 5. Clean up worktrees (before deleting branches)

- Remove the worktree of each **Merged (fast-forward)** branch, and of each confirmed **Merged (verified)** branch: `git worktree remove <path>`
- Prune prunable worktrees: `git worktree prune`
- Do this BEFORE branch deletion. Git refuses to delete a branch that is checked out in a worktree.
- **NEVER force-remove a worktree** (no `--force`). A dirty worktree is already classified as Skip (dirty) and stays untouched.

### 6. Delete merged branches

- **Merged (fast-forward)**: `git branch -d <branch>`
- **Merged (verified)** and confirmed in step 4: `git branch -D <branch>`
- **Use `git branch -D` only on a branch that passed the SHA verification in step 3 AND was confirmed in step 4 of this run.** Never use it on any other branch.
- If `-d` unexpectedly refuses a fast-forward branch, do not escalate to `-D`. Report it as skipped.

### 7. Report summary

Print a summary:

```
Repo: <repo-name>
Branch: main @ <short-sha>
Deleted branches: <list, marking which used -D, or "none">
Skipped branches: <list with reason (diverged / open PR / no PR / dirty / force-delete declined), or "none">
Worktrees removed: <list or "none">
Worktrees pruned: <count or "none">
Worktrees skipped: <list with reason, or "none">
```

Link every PR in the summary as a clickable markdown link.
