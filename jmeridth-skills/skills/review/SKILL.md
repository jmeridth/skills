---
name: review
description: Review a PR (by link or from current context) or the current feature branch using a multi-model, verification-first workflow.
argument-hint: [pr-url | pr-number | branch]
---

## Code Review Workflow

When asked to review a PR (by link or from current context) or the current feature branch, follow this workflow automatically:

### Pull latest first (mandatory)

Before assessing anything or launching agents, sync to the PR's current state. A stale checkout produces findings against code the author has already changed, wasting a full multi-model pass and risking re-opening things that are already fixed.

- Fetch the PR's current head SHA (`gh pr view <pr> --json headRefOid`) and review against that exact SHA — never whatever a local branch or existing worktree happens to point at.
- If you build a worktree, create it at that head SHA. If a worktree already exists, update it to the current head before reading any code, and re-confirm the head has not moved since.
- Read existing review threads and review submission bodies first (`gh api repos/{owner}/{repo}/pulls/{n}/comments`, `.../pulls/{n}/reviews`, and the GraphQL review threads). Note which findings are already raised, or already fixed in a newer commit, and do not re-report them.
- For any cross-repo dependency, fetch it at its own current ref too, never trust a stale local copy.

### First question: should we do this?

Before assessing the diff or launching any review agents, answer "should we do this?" - is the change itself worth making, regardless of how well it is implemented?

- Read the PR description, linked issues, and enough context to understand the intent
- Consider: does this solve a real problem? Is this the right layer/repo for it? Does it duplicate existing functionality? Does it conflict with the project's direction or an existing approach?
- State your answer explicitly in the review output before any findings
- If the answer is "no" or "unclear", stop and raise that with me before doing the line-by-line review - a well-implemented change we should not make is still a change we should not make

### Multi-model review

Scale the number of review agents (and which models) to the size and severity of the change, rather than always using a fixed count.

**First, assess the diff.** Count the changed lines (additions + deletions, **excluding** generated code, vendored deps, and lockfiles such as `go.sum`/`package-lock.json`), and identify what the change touches. Then pick the tier below and **state which tier and models you are using and why**.

| Tier | When | Agents (models) |
|------|------|-----------------|
| **Docs/trivial** | Docs, comments, config, or other non-logic changes only | 1 agent: **Sonnet 5** |
| **Small** | ≤ 150 changed lines, low risk, no security-sensitive paths | 1 agent: **Fable 5** |
| **Medium** | ~150–400 changed lines, **or** any security-sensitive path | 2 agents: **Opus 4.8 + Fable 5** |
| **Large / critical** | > 400 changed lines, **or** high-severity / security-critical surface | 4 agents: **Opus 4.8, Sonnet 5, Haiku 4.5, Fable 5** |

- **Severity overrides size.** Risk bumps the tier **up** regardless of line count: treat auth, crypto/signing, token or secret handling, HTTP handlers, `exec`, SQL, or access-control changes as **at least Medium** even for a tiny diff. When unsure, round up a tier.
- **Fable is always included** except the Docs/trivial tier (which is Sonnet only).
- **For any PR ≤ 150 changed lines, report the size and confirm the tier with me before launching agents.**
- Launch the chosen agents in parallel, each on a different model. **Always display which models were used.**
- Synthesize findings across all models — surface only issues that multiple models flag or that you independently verify. Present a unified, deduplicated report organized by severity.

### Verification standard

- **Every finding must be verified before reporting it.** Do not report potential issues based on assumptions alone.
- Verify by reading the actual source files, checking call sites, tracing data flow, or running tests/experiments
- Clearly label findings with verification status: **Verified** (confirmed by reading code or testing), **Observation** (plausible but depends on context outside the diff), or **Unverified** (could not confirm - include reasoning)
- When a finding involves runtime behavior, write or run a test to confirm it rather than speculating

### Convention rulings need merged precedent

Never rule on a repository convention (version bump size, changelog kind, value style, file placement) from general principles or documented policy alone. Sample 3-5 recently merged PRs of the same change class first and follow demonstrated practice. When documented convention and merged practice conflict, surface the conflict as a question to the maintainers instead of ruling.

Correct:

```
gh pr list --state merged --search "new value" -L 5   # then read how they bumped
"The last four merged PRs adding values shipped as patches, so patch here too."
```

Wrong:

```
"A new value is a feature, so semver says minor."   # instinct, no precedent check
```

**Audit:** Any review comment that dictates a bump size, changelog kind, or structural convention must cite at least one merged PR as precedent. Flag rulings that cite only CONTRIBUTING or semver reasoning.

### Version-target coordination

Before requesting a version change on a chart or package, list every open PR against the same chart, assign explicit non-colliding targets in queue order (first to claim a number keeps it), and state the assignment in each PR. Re-verify the mainline's current version at posting time; never reuse a version read earlier in the session.

Correct:

```
"Main is at 2.0.7 as of this comment. #4061 takes 2.0.8 (claimed first), this PR takes 2.0.9."
```

Wrong:

```
"Bump to 2.1.0."   # two other open PRs already target 2.1.0; churn for all three authors
```

**Audit:** When a review asks for a re-bump, check it names the current mainline version and accounts for sibling open PRs on the same chart.

### Route around other reviewers

If another maintainer has an unresolved thread or a standing changes-requested review on the PR, decide the relationship before writing anything, and say which mode applies:

- **Complement**: cover only what their threads do not; reference theirs instead of restating.
- **Defer**: they are actively driving (recent replies, iterating with the author); stay out unless asked.
- **Coordinate**: your position conflicts with theirs; raise it with the maintainer directly, never as competing review verdicts on the PR.

Never duplicate a concern another reviewer already raised, and never post a verdict that contradicts another maintainer's standing review without talking to them first.

**Audit:** Before posting, list reviewers with unresolved threads or standing reviews. If the list is non-empty and the draft does not reference them, stop and re-check for overlap.

### What to focus on

- **Correctness over style** - only report bugs, logic errors, security issues, race conditions, type mismatches, and missing edge cases. Do not flag style, formatting, naming conventions, or subjective preferences.
- **Check whether the author has addressed existing review feedback** - read through all review threads and comments before reporting. Note unresolved threads.
- **Check for unintended behavioral changes** - compare new code against the existing patterns in the same file or module
- **Check template checklists with both marker styles** - PR checklist boxes appear as `- [x]` or `* [x]`; any scan matching only one style produces false "checklist missing" findings.
- **Check docstring/comment accuracy** - verify that docstrings, comments, and commit messages accurately describe what the code actually does. Flag cases where stated behavior differs from implemented behavior.

### Tone and voice

- For **first-time contributors**, lead with what was done well, be warm and specific about how to fix issues, and provide step-by-step guidance rather than terse criticism
- For established contributors or teammates, be concise and direct
- **Tone down superlatives**: "a good move" over "the right move". Softer assertions feel less prescriptive.
- **Be precise with references**: make it obvious what "this" refers to, e.g. "this suggestion above" not just "this".

### AI attribution

- **Every summary and every PR comment** produced by this skill must start with `:robot:` on the first line so the PR author knows it is an AI-generated review.
- **The overall review summary or verdict comment** (for example the body posted with an approval, or a top-level recap of the whole review) uses `:robot: (summary)`. It is a summary, not a finding, so it carries no severity tag. Individual findings still carry their own severities in their own line comments.
- **Every line-level finding comment** adds, immediately after the `:robot:` emoji, a parenthetical severity tag, with `non-blocking` only when it applies: `:robot: (critical)`, `:robot: (high)`, `:robot: (medium)`, `:robot: (low, non-blocking)`. Severity reflects correctness impact (critical/high/medium/low). **`critical`, `high`, and `medium` are always merge blockers and never get `non-blocking`.** Only `low` (or an other/informational tag) may be marked `non-blocking`, for reporting-fidelity gaps, style-adjacent notes, or anything that need not gate the merge.

### Writing style

Apply these to every summary and every comment. This is load-bearing: a review that ignores it reads as bot noise regardless of how good the findings are.

- **Run the `humanize-comments` skill on every drafted comment body.** Its three passes (shorten, make it sound human, make it non-prescriptive) are the prose rules for this skill. They are not restated here; load that skill and apply it.
- **The `:robot:` attribution prefix is exempt from humanize.** It is a disclosure marker, not prose. Apply humanize to everything after it. Severity lives in the prefix tag only; never repeat severity language ("must fix", "blocker", "nit") in the body.
- **Structure every comment body as claim, then evidence, then ask.** The claim states what goes wrong and its impact. The evidence is the mechanism, not the verification story (no "I traced X" or "I ran Y"; state the conclusion). The ask is a question or observation that leaves the decision with the author, or a suggestion block when the fix is mechanical.
- **Keep the top-level summary short.** Lead with the verdict and any blockers. Positives are optional for established contributors; when included, cap them at 2-3 bullet points, never paragraphs.
- For more prose guidance, see [Refactoring English](https://refactoringenglish.com/contents/) - especially "Get to the Point", "Respect the Reader's Mental Bandwidth", "Verbs Drive the Sentence", "Passive Voice Considered Harmful", "Delete Aggressively", and "Eliminate Ambiguity".

### Drafting comments

- If findings warrant PR comments, draft them in my voice and **show me the draft before posting**
- **Before you show or post any summary or comment, run this checklist:**
  - humanize pass 1 (shorten): one issue, 2-3 sentences, one connector per sentence, no evidence trail
  - humanize pass 2 (human): no severity words, em dashes, headers, bullets, or file:line inside the body
  - humanize pass 3 (non-prescriptive): the ask is a question or observation, not a directive
  - claim, evidence, ask in that order; summary leads with verdict and blockers, positives capped at 2-3 bullets
  - body starts with `:robot:` and the severity tag per the attribution rule
- When specific code changes are needed, use GitHub suggestion blocks
- **Always confirm before approving PRs** unless explicitly told to approve. Asking to see the approval message is not the same as giving the go-ahead.

### Line-level targeting (mandatory)

- **Every PR comment MUST target a specific line in the diff.** Do not post top-level PR comments for code findings.
- Before posting, parse the diff to get the exact file path and line number for each finding. Use `gh api` or `gh pr diff` to get the current diff and extract line numbers.
- Use the GitHub pull request review comments API (`POST /repos/{owner}/{repo}/pulls/{pull_number}/comments`) with these required fields:
  - `path` - relative file path (e.g. `src/handler.go`)
  - `line` - the line number in the diff's new file side
  - `side` - use `RIGHT` for lines in the new version of the file
  - `body` - the comment text (starting with `:robot:`)
  - `commit_id` - the HEAD commit SHA of the PR
- For multi-line comments, also include `start_line` and `start_side` to highlight a range
- When suggesting a concrete fix, use a GitHub suggestion block in the body:

  ````
  :robot: This could be simplified.
  ```suggestion
  replacementCodeHere()
  ```
  ````

- **Never guess line numbers.** Always derive them from the actual diff output. If you cannot determine the exact line, do not post the comment -- surface it in the summary instead.
