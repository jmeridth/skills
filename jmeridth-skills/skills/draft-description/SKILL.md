---
name: draft-description
description: Draft a PR description for the current branch using what/why/notes framework with a magic-word Linear issue reference (Fixes/Closes/Part of). Use when preparing to open a PR.
---

# Draft PR Description

## Steps

### 1. Gather context

```bash
git log main..HEAD --oneline
git diff main...HEAD --stat
```

Read the changed files to understand the full scope of the changes.

### 2. Identify the Linear issue

Check the branch name for a ticket reference (e.g., `ENG-123`, `PROJ-45`). If found, fetch the issue title via the Linear MCP tool to confirm.

If no ticket reference is found in the branch name, ask the user which Linear issue this relates to (or if there is none).

### 3. Draft the description

Use this format:

```markdown
## What

<1-3 sentences describing the concrete change. What does the code do now that it didn't before?>

## Why

<1-3 sentences on motivation. What problem does this solve, or what user need does it address? Reference the Linear issue here with a magic word: `Fixes ENG-123`, `Closes ENG-123`, or `Part of ENG-123`.>

## Notes

<Optional. Implementation details a reviewer should know — tradeoffs, things intentionally left out, follow-up work, migration considerations. Omit this section if there's nothing worth calling out.>
```

Rules:

- Keep it concise. The diff speaks for itself.
- Don't list every file changed.
- Don't repeat the commit messages.
- Never put the Linear ticket in the PR title.
- In the body, reference the Linear issue with a magic word (`Fixes ENG-123`, `Closes ENG-123`, or `Part of ENG-123`) — never bare, never as a markdown link or full URL.
- If the PR is a single small change, the description can be 3-4 lines total.
- Present the draft to the user for review before doing anything with it.

Style:

- Write short, human-readable prose. Complete sentences a teammate can skim, not dense spec language.
- Never use em dashes. Use a period, comma, colon, or parentheses instead.
- Notes are a handful of short bullets at most. Each bullet is one plain sentence, maybe two. No sub-bullets, no bold lead-ins, no severity labels.
- Say what the reviewer needs to know and stop. Cut mechanism detail the diff already shows, validation war stories, and anything that reads like a changelog.
- Don't be prescriptive about product or process decisions (no "should", "must be a flag", "needs a release note"). State the fact and leave the call to the reader.

### 4. Copyedit the draft

Before presenting the draft, apply this pass every time:

- Use active voice and positive statements.
- Prefer specific nouns and verbs over vague abstractions.
- Remove needless words, repeated context, and implementation detail the diff already shows.
- Remove AI-writing tells: puffery, promotional adjectives, empty `-ing` phrases, and stock words such as "delve," "leverage," and "robust."
- Preserve technical meaning and the exact Linear magic-word reference.

The edited draft must be shorter or clearer than the first pass. If an edit only changes tone without improving clarity, omit it.
