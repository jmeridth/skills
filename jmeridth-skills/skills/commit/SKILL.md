---
name: commit
description: Create a meaningful git commit message based on current changes.
argument-hint: [issue-url | issue-id]
---

## Context

- Current status: !`git status`
- Current diff: !`git diff HEAD`
- Current branch: !`git branch --show-current`

## Critical Rules

- **Always ensure you're on a feature branch**
- **Always sign-off my commits** with my git config user.name and user.email
- **Always run tests and lint the code** before creating a git commit
- **NEVER git commit or git push without explicit user approval** - ALWAYS ask first
- **NEVER add any agent as a co-author, only add co-author(s) when the user explicitly requests it**

- Create a meaningful commit message based on the current staged or unstaged changes.
- Ensure it follows the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) specification.
- Use five separate headings (with newlines after each):
  - **What/Why** -- Intent in 1-2 sentences. Combine the what and why into a single concise statement.
  - **Proof it works** -- Tests passed, manual verification steps, or logs.
  - **Risk** -- Risk tier (low/medium/high) and the reason.
  - **AI role** -- Which parts were AI-generated and which were human-written or human-reviewed, plus the AI model and version used (e.g., "Claude Opus 4.6"). If no AI was involved, say so. Always include this heading.
  - **Review focus** -- 1-2 specific areas where human reviewer input matters most.
- Avoid stating obvious facts or padding sections.

## Issue reference

- Find the issue: use the issue-url or issue-id in `$ARGUMENTS`, or look for a GitHub issue number (`#123`) or Linear key (e.g., `ENG-123`) in the branch name. When only an id is given, fetch the issue with the Linear MCP server or `gh issue view` to confirm its scope.
- If no issue applies, add no reference line.
- Put the reference on the first line after the commit title.
- **Deduce the keyword yourself** - do not ask. Compare the issue against the commit's full diff:
  - The commit fully resolves what the issue asks for -> use `Fixes` (bugs) or `Closes` (features/tasks).
  - The commit is partial progress, or only touches the issue's topic -> use `Relates to` for GitHub issues or `Part of` for Linear issues.
- **`Relates to` / `Part of` is not the safe default.** Picking it "to be safe" when the commit resolves the issue leaves the issue open, which is worse than the reverse mistake.
- GitHub issues in another repository use the full form (`Fixes owner/repo#<n>`).
- Reference Linear issues by bare key after the keyword (`Fixes ENG-123`, `Part of ENG-123`). Never as a markdown link or full URL. Never in the commit title.
- **No closing keywords in prose**: Never write GitHub closing keywords (`fix`/`fixes`/`fixed`, `close`/`closes`/`closed`, `resolve`/`resolves`/`resolved`, with or without a colon) directly before an issue number in the body. GitHub treats `fixes #123` anywhere in the message as a close once the commit reaches the default branch. Keep these keywords on the reference line. When only mentioning an issue in prose, write "see #123".
