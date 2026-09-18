# jmeridth/skills

Jason Meridth's personal [Claude Code](https://docs.claude.com/en/docs/claude-code) marketplace.

This repo is a Claude Code plugin marketplace named `jmeridth`. It ships a single
plugin, `jmeridth-skills`, bundling the skills I use across my projects for git,
GitHub, Go, code review, and day-to-day productivity.

## Install

Add the marketplace, then install the plugin.

From inside Claude Code:

```
/plugin marketplace add jmeridth/skills
/plugin install jmeridth-skills@jmeridth
```

Or from your shell:

```bash
claude plugins marketplace add jmeridth/skills
claude plugins install jmeridth-skills@jmeridth
```

Once installed, the skills are available in every repo you work in. Claude invokes
them automatically when a task matches a skill's description, or you can call one
directly by name (for example `/commit`).

## Update

```bash
claude plugins marketplace update jmeridth
```

New and changed skills arrive with the update. No per-repo setup is required.

## Skills

| Skill | What it does |
| --- | --- |
| `commit` | Create a meaningful git commit message based on the current changes. |
| `pr` | Create a good pull request. |
| `pr-comments` | Fetch, assess, and address PR review comments, then reply and resolve threads. |
| `review` | Review a PR or the current feature branch with a multi-model, verification-first workflow. |
| `reassess` | Scan open PRs for new comments on yours, stale reviews, and PRs awaiting review. |
| `repo-reset` | Pull latest main, switch to it, then clean up merged branches and worktrees. |
| `gha-standards` | GitHub Actions workflow standards: security hardening, permissions, conventions. |
| `go-standards` | Go coding standards: syntax preferences, libraries, code quality, package design, testing. |
| `go-security-review` | Security-focused differential review of Go changes with regression test generation. |
| `skill-authoring` | Enforce the agentskills.io specification when creating or auditing skills. |
| `obsidian-daily` | Summarize recent work into today's Obsidian daily note without duplicating. |
| `humanize-comments` | Rewrite review, doc, and issue comments so they read short, plain, and non-prescriptive. |
| `draft-description` | Draft a PR description using a what/why/notes format with a Linear magic-word reference. |
| `writing-clearly-and-concisely` | Apply Strunk's rules for clear prose and flag common AI writing patterns. |

## Uninstall

```bash
claude plugins uninstall jmeridth-skills@jmeridth
claude plugins marketplace remove jmeridth
```

## License

[MIT](LICENSE)
