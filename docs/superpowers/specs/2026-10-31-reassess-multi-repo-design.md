# Design: multi-repo `reassess refresh`

Date: 2026-10-31
Repo: `jmeridth/skills`
Status: awaiting Jason's approval

## Intent

`reassess` triages open PRs for one repo. Jason monitors many repos across several orgs and wants one run that triages all of them. Today that means invoking `reassess` per repo and reading N tables.

Extend `reassess` so `reassess refresh` reads a config file listing orgs and repos, triages them all, and prints one report. Keep the single-repo behavior unchanged.

## Goals

- `/reassess` and `/reassess owner/repo` behave exactly as today.
- `/reassess refresh` assesses every monitored repo from `~/.config/jmeridth-skills/config.yaml`.
- Candidate discovery uses `gh search prs`, not per-repo loops, to stay inside API rate limits.
- Deterministic logic (config parsing, filtering, search-query building, bucket classification) lives in a tested script. The agent handles the report, approval, and handoff.
- Scope stays narrow by default. The config is read only when `refresh` is passed.

## Non-goals

- No background polling in v1. `/loop` or `/schedule` can wrap `refresh` later. The skill gets one sentence saying so and nothing built.
- No cache or state file. Every run queries fresh, as `reassess` already requires.
- No new skill. `reassess` is extended in place.
- No change to the `review` or `pr-comments` skills.

## Anti-goals

- A `refresh` that silently falls back to the current repo when the config is bad.
- Any run that triages archived repos.
- Any post, comment, resolve, or draft-move without per-PR approval (existing rule, unchanged).

## Invocation

| Command | Behavior |
| --- | --- |
| `/reassess` | current repo (directory), as today |
| `/reassess owner/repo` | that repo, as today |
| `/reassess refresh` | all monitored repos from the config |

## Config

Path: `~/.config/jmeridth-skills/config.yaml`

```yaml
default_clone_path: ~/code
monitor:
  - org: my-org
    exclude: [legacy-thing, sandbox]
  - repo: other-org/one-repo
    path: ~/work/one-repo   # optional clone path override
```

- `org` entries cover every repo in the org. `exclude` lists repo names (not `owner/name`) to drop.
- `repo` entries name one `owner/name`. `path` is optional.
- Archived repos are always excluded: `archived:false` in the search, plus a client-side check on the result.
- Clone path for a repo is `path` if set, else `<default_clone_path>/<repo-name>`.
- A missing config file, invalid YAML, or a schema violation stops the run with an error and prints the expected schema. No fallback to the current repo. (Builder's call: exit non-zero, message to stderr.)

## Components

1. `jmeridth-skills/skills/reassess/scripts/reassess-candidates` (bash, `jq`, `yq`, `gh`). Ships with the plugin. Called from `SKILL.md` through `${CLAUDE_PLUGIN_ROOT}`.
   - Reads and validates the config.
   - Runs `gh search prs` per `(org or repo) x (review-requested, author, reviewed-by, commenter)`.
   - Drops archived repos, excluded repos, and drafts authored by others.
   - Fetches per-PR detail only for candidates.
   - Classifies each PR into bucket A, B, or C (highest priority wins: A, then B, then C) and sets the draft-candidate flag, using the rules already in `SKILL.md` steps 4 and 4.5.
   - Prints JSON: one object per PR with `repo`, `number`, `title`, `author`, `bucket`, `draft_candidate`, `reasons`, `updatedAt`, `clone_path`.
   - Stops on a search rate-limit error and reports it. No retry.
2. `jmeridth-skills/skills/reassess/SKILL.md` edits:
   - Document the `refresh` argument.
   - Replace the prose rules in steps 3, 4, and 4.5 with a call to the script for all modes. The script takes either a single `owner/repo` or `--config`.
   - In `refresh` mode, run the script, then render one table with a `Repo` column, grouped by bucket and sorted by `updatedAt` descending.
   - Sync step: for each repo with an existing clone, pull the default branch first. If the clone directory is missing, skip the pull and say so in the report. The stale-checkout rule still applies: never compute version targets or conflict state from an unsynced checkout.
   - Approval and handoff to `review` and `pr-comments` work as today. Every handoff passes the repo explicitly.
   - All existing rules stay (read-only through the report, fresh queries, same-login provenance guard, resolved threads ignored, UTC timestamps).
3. Tests in `tests/reassess/` (repo root, not shipped): `bats` tests with a stub `gh` on `PATH` returning fixture JSON.
   - Config: valid, missing, malformed, schema violations, `exclude`, archived filtering, clone-path resolution.
   - Search queries: correct qualifiers per org and repo entry.
   - Classification: A/B/C by timestamp, priority dedupe, bot-comment exclusion, resolved-thread exclusion, draft candidates (failing required checks, stale after 7 days), rate-limit stop.
4. CI and tooling:
   - `just test` runs `bats tests/`.
   - `.github/workflows/test.yaml` runs `just test`, following `gha-standards` (SHA-pinned actions, least-privilege permissions, harden-runner).
   - `shellcheck` and `shfmt` hooks in `.pre-commit-config.yaml`.
   - Add `test` to the required checks in the `main` ruleset. Jason approved this; it is a settings change made after the workflow has run once on a PR so the check name exists.
   - Bump `plugin.json` to the next free version (0.1.19 as of 2026-10-31; check `origin/main` first).

## Constraints

- Plugin ships source only. No compile step, no package install. Runtime needs `gh`, `jq`, `yq`, bash.
- GitHub search API allows about 30 requests per minute. A config with a few orgs must stay well under that.
- Markdown lint and pre-commit must pass.

## Decided by Jason

- Extend `reassess`, no separate skill.
- Config read only when an argument asks for it.
- Config path `~/.config/jmeridth-skills/config.yaml`, with `default_clone_path` (his: `~/code`).
- Orgs plus single repos, `exclude` list, archived always excluded.
- `gh search prs` for discovery.
- Explicit refresh, no polling in v1, polling as a later option.
- Bash + `jq` + `yq` + `bats`; test check required in the ruleset.
- The script is the single source of truth for bucket and draft-candidate rules. It serves both `/reassess`, `/reassess owner/repo`, and `/reassess refresh`. `SKILL.md` steps 4 and 4.5 shrink to "run the script". User-facing behavior of the single-repo modes stays identical. Single-repo modes need no config, so they do not require `yq`.

## My calls (not yet confirmed by Jason)

- The argument keyword is `refresh`.
- Bad config stops the run; no fallback.
- Branch, implement, and open a draft PR through the `pr` skill after this design is approved.

## Calls made after builder review (mine, not yet confirmed by Jason)

- **Identity:** "me" is the `gh` authenticated login (`gh api user`), as `reassess` already does. One account per run. Multi-account configs are out of scope.
- **Batching:** each `org` entry gets one query per role using `org:`. `repo` entries batch into chunked queries with several `repo:` qualifiers per search. The cost is roughly 4 queries per org plus 4 per chunk, so the 30/min limit holds for realistic configs.
- **Rate limit or truncation:** a rate-limit error fails the whole run with a non-zero exit and no partial JSON, so an incomplete triage never looks complete. If any search hits the 1000-result cap, the output sets `truncated: true` with the affected query, and the report says so.
- **Sync safety:** the sync step never stashes, switches branches, or resets. It runs `git pull --ff-only` only when the clone is on its default branch with a clean tree. Otherwise it skips that repo and the report flags it (dirty tree, wrong branch, diverged, or pull failed). Unsynced repos get no version targets or conflict states.
- **Default branch:** from `git symbolic-ref refs/remotes/origin/HEAD` in the clone, falling back to `gh repo view --json defaultBranchRef`.
- **Required checks:** `gh pr checks --required`, as today. If it errors, skip the failing-checks flag for that PR and note it in `reasons`.
- **Ruleset change:** not part of the PR. After `test` runs green once on the PR, I show the `gh api` command and run it only after Jason confirms.
- **yq:** Mike Farah's Go `yq` (v4). The script checks `yq --version` and fails with a clear message otherwise.
- **Overlap:** dedupe on lowercase `owner/name`. An explicit `repo` entry beats an org `exclude`.
- **Judgment stays with the agent:** the script computes everything timestamp- and flag-based. The agent applies the same-login provenance guard and decides whether a bot review has actionable inline comments, using the script's `reasons` and raw activity fields.

## Left to the builder

- Script name, internal function layout, JSON field order.
- Fixture design and stub-`gh` mechanics.
- How `reasons` strings read.
- Exact `gh search` pagination handling, within the rate-limit constraint.
