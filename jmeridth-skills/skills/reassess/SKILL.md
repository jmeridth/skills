---
name: reassess
description: Scan open pull requests on the current repository (or a repo passed in) and surface the ones needing attention. Finds PRs you authored that have new comments, PRs you reviewed where the author has since pushed updates, and new PRs awaiting your review. Use when the user says "reassess", "assess PRs", "check my PRs", "any PR updates", or "what PRs need my attention". Hands off to the pr-comments and review skills when available.
argument-hint: [owner/repo]
---

## Reassess Workflow

When invoked, follow this workflow automatically. Steps 1-5 are read-only. Never make changes, post comments, or launch reviews before the user approves in step 6.

### 0. Sync local state first (mandatory)

If a local clone of the target repository exists, pull the latest default branch before any assessment: `git pull upstream main` (or `origin`). Never compute version targets, conflict states, or "what changed" against a stale checkout, and never rely on repo state read earlier in the session.

Correct:

```bash
git -C ~/code/repo checkout main -q && git -C ~/code/repo pull -q upstream main
```

Wrong: reusing a chart version or merge state fetched hours earlier; it produces pings to already-merged PRs and wrong re-bump targets.

**Audit:** The first command of every reassessment run is the pull. If it is missing from the transcript, the run is invalid.

### 1. Resolve the repository

- If an argument was given (`owner/repo` or a repo URL), use it and pass `--repo owner/repo` to every `gh` command below
- Otherwise detect from the current directory: `gh repo view --json nameWithOwner --jq .nameWithOwner`
- If neither works, ask the user which repository to assess

### 2. Identify the user

- Get the authenticated login: `gh api user --jq .login`
- Use this login (not a hardcoded name) for all authorship and reviewer comparisons below

### 3. List open pull requests

```bash
gh pr list --state open --limit 100 \
  --json number,title,author,isDraft,updatedAt,reviewDecision,headRefOid
```

- If exactly 100 results come back, say so and note the list may be truncated
- Skip drafts authored by others (they are not ready for review). Keep your own drafts, since comments can still arrive on them

### 4. Classify each PR into one of three buckets

#### A. My PRs with new activity

PRs authored by the login from step 2:

- Fetch all activity: `gh pr view {number} --json comments,reviews,commits`
- Also fetch inline review comments: `gh api repos/{owner}/{repo}/pulls/{number}/comments`
- Find the newest comment or review **not written by me** and skip bot noise (logins ending in `[bot]`, e.g. `dependabot[bot]`, `github-actions[bot]`) unless it is a review with actionable inline comments
- Find **my** last activity on the PR: the later of my last pushed commit and my last comment or reply
- If someone else's activity is newer than mine, the PR goes in bucket A - there is feedback I have not addressed
- If a review thread is already resolved, do not count it as new activity

#### B. PRs I reviewed where the author has pushed updates

- Candidates: `gh pr list --state open --search "reviewed-by:{login}"` **plus** `gh pr list --state open --search "commenter:{login}"`, minus my own PRs. Substantive comment-form feedback counts the same as a formal review; the author cannot tell the difference and neither should the triage.
- For commenter-only candidates, compare my last comment time against the head commit time instead of a review `submittedAt`
- For each, get my latest review time (`gh pr view {number} --json reviews`, filter to my login, take the newest `submittedAt`) and the head commit time (`gh pr view {number} --json commits`, take the last `committedDate`)
- If the head commit is newer than my last review, the PR goes in bucket B - my review is stale and needs a re-review
- If my last review was an approval and nothing else changed besides the new commits, still include it, but note it was previously approved

#### C. New PRs that need review

- Explicit requests: `gh pr list --state open --search "review-requested:{login}" --json number,title,author`
- Plus any open non-draft PR not authored by me where I have left no review and no comment
- Exclude PRs already in bucket B

A PR can qualify for more than one bucket (e.g. the author replied to my review AND pushed commits). List it once, in the highest-priority bucket: A, then B, then C.

### 4.5 Flag draft candidates

In addition to its bucket, flag any non-draft PR **not authored by me** as a **draft candidate** if either condition holds:

- **Failing required checks**: `gh pr checks {number} --required` reports one or more failures. Only count required checks; ignore failing optional checks
- **Stale after my review**: I have reviewed the PR, and the author has made no updates (no commits, no comments, no pushes) in the 7 days after my latest review. Compare the PR's last author activity against my latest review `submittedAt`, using the current UTC time from `date -u +%Y-%m-%dT%H:%M:%SZ`

This is a flag, not a bucket - a PR keeps its bucket (or no bucket) and additionally shows as a draft candidate. Never flag my own PRs or PRs already in draft.

### 5. Report the assessment

Print a summary table before doing anything else:

```
| PR | Title | Author | Bucket | What changed | Recommended action |
| --- | --- | --- | --- | --- | --- |
| #12 | Fix race in worker pool | alice | B | 2 commits since my review | re-review (review skill) |
| #15 | Add retry logic | me | A | 3 new comments from bob | address comments (pr-comments skill) |
| #17 | Refactor config loader | carol | - | required CI failing; no updates in 9 days since my review | move to draft? |
```

- For each draft candidate, state the reason (failing required checks, stale after review, or both) in the "What changed" column and set the recommended action to "move to draft?"

- If all buckets are empty, say "All caught up - no PRs need attention" and stop
- Sort within each bucket by `updatedAt`, most recent first

### 6. Wait for approval, then act

Ask the user which PRs to act on. Never proceed without an explicit choice. Then, one PR at a time:

- **Bucket A** (my PR, new comments): invoke the `pr-comments` skill with the PR number. If that skill is not available, fall back to fetching the comments manually, assessing each one, and presenting fixes for approval
- **Bucket B** (stale review): invoke the `review` skill with the PR number, and tell it to focus on the delta since my last review (the commits pushed after my `submittedAt`)
- **Bucket C** (needs first review): invoke the `review` skill with the PR number for a full review
- **Draft candidates**: ask the user explicitly, per PR, whether to move it to draft. On approval, run `gh pr ready {number} --undo`. If the command fails for lack of permission (write access is required to draft someone else's PR), report that and move on - do not retry or work around it. Never move a PR to draft without explicit per-PR approval
- If neither skill is available, say so and offer a manual `gh` based workflow instead of silently improvising

### Rules

- Steps 1-5 are strictly read-only: no posting, no committing, no resolving threads
- Always use the authenticated login from step 2, never assume the username
- **Same-login provenance guard**: reviews and comments under the authenticated login may be the human's own work, not the agent's. If a review from that login is not in session context, treat it as human-authored: read it before acting, never post anything that contradicts or dismisses it, and hand clearance of the human's own changes-requested review back to the human
- Always ignore resolved review threads when deciding whether a PR has new activity
- Always compare timestamps in UTC as returned by the API; do not parse them into local time
- If `gh` is not authenticated (`gh auth status` fails), stop and tell the user to run `gh auth login`
- When handing off to `pr-comments` or `review`, pass the repo explicitly if it was passed in as an argument, since the skill may run outside that repo's directory
