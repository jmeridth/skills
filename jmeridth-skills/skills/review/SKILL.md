---
name: review
description: Review a PR (by link or from current context) or the current feature branch using a multi-model, verification-first workflow.
argument-hint: [pr-url | pr-number | branch]
---

## Code Review Workflow

When asked to review a PR (by link or from current context) or the current feature branch, follow this workflow automatically:

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

### What to focus on

- **Correctness over style** - only report bugs, logic errors, security issues, race conditions, type mismatches, and missing edge cases. Do not flag style, formatting, naming conventions, or subjective preferences.
- **Check whether the author has addressed existing review feedback** - read through all review threads and comments before reporting. Note unresolved threads.
- **Check for unintended behavioral changes** - compare new code against the existing patterns in the same file or module
- **Check docstring/comment accuracy** - verify that docstrings, comments, and commit messages accurately describe what the code actually does. Flag cases where stated behavior differs from implemented behavior.

### Tone and voice

- Use additive, curious framing - not corrective or prescriptive
- For **first-time contributors**, lead with what was done well, be warm and specific about how to fix issues, and provide step-by-step guidance rather than terse criticism
- For established contributors or teammates, be concise and direct

### AI attribution

- **Every summary and every PR comment** produced by this skill must start with `:robot:` on the first line so the PR author knows it is an AI-generated review.
- **The overall review summary or verdict comment** (for example the body posted with an approval, or a top-level recap of the whole review) uses `:robot: (summary)`. It is a summary, not a finding, so it carries no severity tag. Individual findings still carry their own severities in their own line comments.
- **Every line-level finding comment** adds, immediately after the `:robot:` emoji, a parenthetical severity tag, with `non-blocking` only when it applies: `:robot: (critical)`, `:robot: (high)`, `:robot: (medium)`, `:robot: (low, non-blocking)`. Severity reflects correctness impact (critical/high/medium/low). **`critical`, `high`, and `medium` are always merge blockers and never get `non-blocking`.** Only `low` (or an other/informational tag) may be marked `non-blocking`, for reporting-fidelity gaps, style-adjacent notes, or anything that need not gate the merge.

### Drafting comments

- If findings warrant PR comments, draft them in my voice and **show me the draft before posting**
- When specific code changes are needed, use GitHub suggestion blocks
- One actionable point per comment - do not bundle multiple concerns
- Each comment must begin with `:robot:` per the attribution rule above

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
