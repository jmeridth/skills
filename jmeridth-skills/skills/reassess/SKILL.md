---
name: reassess
description: Scan open pull requests on the current repository, a repo passed in, or every monitored repo (refresh), and surface the ones needing attention. Finds PRs you authored that have new comments, PRs you reviewed where the author has since pushed updates, and new PRs awaiting your review. Use when the user says "reassess", "reassess refresh", "assess PRs", "check my PRs", "any PR updates", or "what PRs need my attention". Hands off to the pr-comments and review skills when available.
argument-hint: [owner/repo | refresh]
---

## Reassess Workflow

When invoked, follow this workflow automatically. Steps 1-4 never post, comment, resolve, or launch anything. The one write is the script's clone sync: a `git fetch` and a fast-forward of clean clones on their default branch (details in step 2). Never make other changes, post comments, or launch reviews before the user answers with row numbers in step 5.

A script does the deterministic work: discovery, bucket and draft-candidate classification, and clone sync. It is the single source of truth for those rules. Do not recompute them by hand. Your job is the judgment around its output.

| Argument | Scope |
| --- | --- |
| none | the repository in the current directory |
| `owner/repo` (or a repo URL) | that repository |
| `refresh` | every org and repo in `~/.config/jmeridth-skills/config.yaml` |

The config is read only for `refresh`. Never read it, or widen the scope, unless the user asked for it.

### 1. Resolve the scope

- `refresh`: no repo needed. Go to step 2
- Argument given: normalize a repo URL to `owner/repo`
- No argument: detect from the current directory with `gh repo view --json nameWithOwner --jq .nameWithOwner`
- If none of these work, ask the user which repository to assess

### 2. Run the script (mandatory, always first)

The script sits next to this file, at `scripts/reassess-candidates` under this skill's base directory. Run it as the first reassessment command, after resolving the scope in step 1:

```bash
SCRIPT=<skill base directory>/scripts/reassess-candidates
"$SCRIPT" owner/repo                                          # single repo
"$SCRIPT" --config ~/.config/jmeridth-skills/config.yaml      # refresh
```

It searches with `gh search prs`, fetches detail for the candidates only, classifies them, looks up PRs I reviewed or commented on that closed recently, then syncs the local clone of each repo that has rows, and prints one JSON object. The sync runs `git fetch` and `git merge --ff-only`, and only on a clean tree on the default branch. A repo with no rows gets no `sync` entry. If the script is missing from the transcript, the run is invalid.

The recently closed window defaults to 3 days. Pass `--closed-since 24h` (or `7d`, and so on) only when the user asks for a different window.

Exit codes:

- `0`: success
- `2`: config problem. Relay the error and the expected schema it printed, then stop. Do not fall back to the current repo
- `3`: GitHub rate limit. Report it and stop. Do not retry and do not guess from partial data
- `4`: `gh` is not authenticated. Tell the user to run `gh auth login`
- `1`: anything else. Show stderr and stop

Output:

```json
{
  "prs": [{"repo": "", "number": 0, "title": "", "author": "", "bucket": "A|B|C|null",
           "isDraft": false, "draft_candidate": false, "maintainer_wait": false,
           "reasons": [], "roles": [], "updatedAt": "", "clone_path": "or null",
           "raw": {"last_other_activity": "", "my_last_activity": "", "my_last_review": "",
                   "my_last_touch": "", "head_commit": "",
                   "last_maintainer_activity": "or null", "author_last_activity": "or null"}}],
  "closed": [{"repo": "", "number": 0, "title": "", "author": "", "roles": [],
              "state": "MERGED|CLOSED", "closedAt": "", "mergedBy": "or null"}],
  "sync": [{"repo": "", "status": "synced|skipped", "reason": "", "clone_path": "or null"}],
  "truncated": [{"query": ""}]
}
```

What the buckets mean (the script applies these; use them to explain, not to recompute):

- **A**: my PR where someone else's activity is newer than mine. Resolved threads and plain bot noise are ignored
- **B**: a PR I reviewed or commented on where the head commit is newer than my last touch
- **C**: a PR by someone else, not a draft, where I left no review or comment. Single-repo mode considers every open PR in the repo. `refresh` considers only PRs with a review request, to keep org-wide runs bounded
- A PR appears once, in the highest bucket (A, then B, then C)
- **Maintainer wait** (`maintainer_wait: true`) is a flag on bucket C rows: another maintainer (a non-bot `MEMBER`, `OWNER`, or `COLLABORATOR` who is neither me nor the author) has commented, reviewed, or left an inline comment (approvals and resolved threads do not count), and the later of their last engagement and the author's last activity is under 7 days old. The author gets 7 days to respond before I pile on. The row keeps its bucket and its place in the sort, and `reasons` says who engaged or when the author was last active
- The wait does not apply when the PR requests my review and another maintainer @-mentioned me in a comment or review. `reasons` then names who asked
- Bucket B rows are never gated. When another maintainer has engaged, `reasons` notes it
- **Draft candidate** is a flag, not a bucket: required checks failing, or no author activity 7+ days after my review. It never applies to my PRs or drafts
- **Closed**: a PR I reviewed or commented on that merged or closed inside the window, newest first. It is never a row and never takes an action. A PR reopened since then is left out, since the open searches report it

### 3. Apply judgment

- **Same-login provenance guard**: reviews and comments under the authenticated login may be the human's own work, not the agent's. If a review from that login is not in session context, treat it as human-authored: read it before acting, never post anything that contradicts or dismisses it, and hand clearance of the human's own changes-requested review back to the human
- **Bot reviews**: when `reasons` mentions a bot review with inline comments, read those comments and say whether they are actionable
- **Stale local state**: for every `sync` entry with `status: skipped`, say why (no clone, dirty tree, not on the default branch, diverged, ahead of remote, pull failed). Never compute version targets, conflict states, or "what changed" from a checkout the script did not sync
- **Truncation**: if `truncated` is not empty, say the listed searches hit the 1000-result cap and the report may be incomplete
- **Checks**: if `reasons` says required checks were unavailable, say the draft-candidate check was skipped for that PR

### 4. Report the assessment

Print one table before doing anything else. Number every row, starting at 1 and counting straight through all buckets without restarting, so the user can answer with row numbers. In `refresh` mode include the `Repo` column. In single-repo mode, drop it.

```
| # | Repo | PR | Title | Author | Bucket | What changed | Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | o/api | #15 | Add retry logic | me | A | new feedback from bob | comments |
| 2 | o/api | #12 | Fix race in worker pool | alice | B | 2 commits since my review | review |
| 3 | o/web | #17 | Refactor config loader | carol | - | required checks failing: build | draft |
| 4 | o/web | #19 | Add audit log | dave | C | waiting on author: erin engaged 2 days ago | wait |
```

- Link every PR as a clickable markdown link
- The `Action` column is the recommended action, one word from the list in step 5. Bucket A gets `comments`, B and C get `review`, a C row with `maintainer_wait: true` gets `wait`, and a draft candidate with no bucket gets `draft`
- A draft candidate that also has a bucket keeps the bucket's action. Say "also draft candidate: {reason}" in the `What changed` column. The user can still answer `draft` for that row
- The script already sorts rows by bucket, then `updatedAt`, newest first. Keep that order and number in that order
- After the table, when `closed` is not empty, list it under "Merged or closed recently", one line per PR: link, title, `merged by {mergedBy}` or `closed without merging`, and `closedAt`. No row numbers. Never say a PR's state is unconfirmed when it appears here; when a PR acted on earlier in the session is in neither `prs` nor `closed`, look it up with `gh pr view` instead of guessing
- If `prs` is empty and `truncated` is empty, say "All caught up - no PRs need attention", still list `closed` if it is not empty, and stop. If `truncated` is not empty, say the result may be incomplete instead
- End the report with one line telling the user how to answer: `Reply with row numbers and an action, for example "1 comments, 2-4 review, 5 draft, 6 skip". A bare number runs the Action shown; on a wait row it does nothing.`

### 5. Wait for approval, then act

Wait for the user to answer with row numbers. Never act without an explicit answer.

Actions the user can give:

| Action | What it does |
| --- | --- |
| `review` | Invoke the `review` skill. Bucket B: tell it to focus on the delta since `raw.my_last_touch`, the later of my last review or comment. Bucket C: a full review |
| `comments` | Invoke the `pr-comments` skill. Bucket A rows |
| `draft` | Move the PR to draft with `gh pr ready {number} --repo {repo} --undo`. Valid on any row flagged as a draft candidate |
| `wait` | Do nothing yet: another maintainer is waiting on the author. A bare number on a `wait` row does nothing. The user can still answer `review` for the row to review it anyway |
| `details` | Show the row's `reasons` and `raw` timestamps. Changes nothing |
| `skip` | Do nothing with the row |

Reading the answer:

- Accept single numbers, lists (`1,3,5`), and ranges (`2-4`), each followed by an action. A bare number means the action in the `Action` column
- Numbers refer to the most recent table only. After a new run, renumber and ignore numbers from older tables
- If a number does not exist, an action does not fit the row (for example `comments` on a bucket B row), or the answer is ambiguous, ask one short question. Do not guess
- Before acting, echo the parsed plan in one line per row, for example `2 review o/api#12`, then proceed. Do not ask for a second confirmation
- A row number with `draft` is the explicit per-PR approval the draft rule needs. A number without `draft` never moves a PR to draft
- If `draft` fails for lack of permission (write access is required to draft someone else's PR), report that and move on. Do not retry or work around it
- If the `review` or `pr-comments` skill is not available, say so and offer a manual `gh` based workflow instead of silently improvising
- Always pass the repo explicitly when handing off, since the skill may run outside that repo's directory

When several rows get `review`, the `review` skill can run them concurrently in separate orchestrator subagents.

### Rules

- Steps 1-4 never post, commit, or resolve threads. The only write is the script's clone sync (fetch plus fast-forward of clean default-branch clones)
- Always use the authenticated login (the script reads it from `gh api user`), never assume the username
- **Fresh queries every invocation**: run the script again on every invocation. Never carry forward bucket assignments or "unchanged since" judgments from an earlier run in the same session; human activity between runs (an approval, a review, a push) is exactly what this workflow exists to catch. Audit: a run whose transcript reuses a prior run's table without re-running the script is invalid
- `refresh` runs only when the user asks. Nothing polls in the background. A recurring check can wrap `reassess refresh` later with `/loop` or `/schedule`
- Always ignore resolved review threads when deciding whether a PR has new activity (the script already does)
- Timestamps compare in UTC as the API returns them; do not parse them into local time
- When handing off to `pr-comments` or `review`, pass the repo explicitly
