# reassess multi-repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `reassess refresh` triages every repo in `~/.config/jmeridth-skills/config.yaml` through one tested script that also serves the single-repo modes.

**Architecture:** One bash script, `reassess-candidates`, reads the config, discovers PRs with `gh search prs`, fetches detail for candidates, classifies buckets A/B/C and draft candidates, and prints JSON. `SKILL.md` runs it and keeps only the judgment steps (report, approval, handoff, provenance guard). `bats` tests drive the script with a stub `gh` on `PATH`.

**Tech Stack:** bash, `jq`, `yq` (Mike Farah v4), `gh`, `bats`, `shellcheck`, `shfmt`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-31-reassess-multi-repo-design.md`

## Global Constraints

- Config path: `~/.config/jmeridth-skills/config.yaml`. Keys: `default_clone_path`, `monitor[]` with `org` (+ `exclude: [names]`) or `repo` (+ optional `path`).
- Archived repos are always excluded (`archived:false` in search, plus a client-side check).
- Clone path is `path` if set, else `<default_clone_path>/<repo-name>`.
- "me" is `gh api user --jq .login`. One account per run.
- Rate-limit error: fail the whole run, non-zero exit, no partial JSON. 1000-result cap: set `truncated`.
- Sync: `git pull --ff-only` only on a clean tree on the default branch. Never stash, switch, or reset.
- Dedupe on lowercase `owner/name`. An explicit `repo` entry beats an org `exclude`.
- Priority when a PR qualifies for several buckets: A, then B, then C. Draft candidate is a flag, not a bucket, and never applies to my PRs or drafts.
- Draft-candidate rules: failing required checks (`gh pr checks --required`), or no author activity for 7 days after my latest review.
- Timestamps compare as UTC strings from the API, never parsed to local time.
- Plugin files under `jmeridth-skills/` changing requires a `plugin.json` bump above `origin/main` (0.1.18 as of 2026-10-31, so 0.1.19; recheck before the PR).
- Exit codes: `2` config error, `3` rate limit, `4` `gh` not authenticated, `1` anything else.
- Single-repo modes must not require `yq` or a config file.
- Follow `gha-standards`: SHA-pinned actions, `permissions: {}` at top, least privilege per job, harden-runner first.
- Commit messages and the PR go through the `commit` and `pr` skills.

## Review Focus

- An `org` entry that matches zero PRs: empty `prs`, exit 0, not an error.
- `committedDate` equal to my last review time: not stale.
- `gh auth status` failing: exit 4 with a "run gh auth login" message.
- `~` and trailing slashes in `default_clone_path` and `path`.
- A PR I authored that also appears in the `commenter` and `reviewed-by` searches: one row, bucket A.

## File Structure

- Create `jmeridth-skills/skills/reassess/scripts/reassess-candidates`: the script, executable.
- Create `tests/reassess/helpers.bash`: shared bats setup, stub `gh` install.
- Create `tests/reassess/bin/gh`: the stub.
- Create `tests/reassess/fixtures/`: JSON fixtures.
- Create `tests/reassess/{smoke,config,search,classify,sync}.bats`.
- Create `.github/workflows/test.yaml`.
- Modify `justfile`, `.pre-commit-config.yaml`, `jmeridth-skills/skills/reassess/SKILL.md`, `jmeridth-skills/.claude-plugin/plugin.json`.

## Output contract

```json
{
  "prs": [{"repo":"o/r","number":1,"title":"","author":"","bucket":"A|B|C|null","draft_candidate":false,"reasons":[],"updatedAt":"","clone_path":"","raw":{"last_other_activity":"","my_last_activity":"","my_last_review":"","head_commit":""}}],
  "sync": [{"repo":"o/r","status":"synced|skipped","reason":""}],
  "truncated": [{"query":""}]
}
```

`raw` carries the activity fields the agent needs for the provenance guard and bot-review judgment.

---

### Task 1: Tooling, stub `gh`, and script skeleton

**Files:**

- Create: `jmeridth-skills/skills/reassess/scripts/reassess-candidates`, `tests/reassess/helpers.bash`, `tests/reassess/bin/gh`, `tests/reassess/smoke.bats`, `.github/workflows/test.yaml`
- Modify: `justfile`, `.pre-commit-config.yaml`

**Interfaces:**

- Produces: script CLI `reassess-candidates [owner/repo | --config PATH] [--dump-config]`. With neither a repo nor `--config`, it prints usage and exits 1. `--help` exits 0.
- Produces: `helpers.bash` function `setup_stub` that prepends `tests/reassess/bin` to `PATH`, sets `GH_STUB_DIR` to a per-test temp dir, and truncates `$GH_STUB_DIR/calls.log`.
- Produces: stub `gh` contract. It appends its full argv to `$GH_STUB_DIR/calls.log`. It answers `api user` with `$GH_STUB_DIR/user` contents. For every other call it prints `$GH_STUB_DIR/<arg1>_<arg2>.json` (for example `search_prs.json`, `pr_view.json`, `pr_checks.json`, `api.json`), with an optional more specific file `<arg1>_<arg2>__<slug>.json` where `<slug>` is any single argv element after `--`-flag stripping and non-alphanumerics replaced with `_`. If `$GH_STUB_FAIL_MATCH` is set and the joined argv contains it, print `HTTP 403: API rate limit exceeded` to stderr and exit 1. `gh auth status` exits 0 unless `$GH_STUB_UNAUTH` is set.

- [ ] **Step 1: Write the failing test** in `tests/reassess/smoke.bats`: `script prints usage with --help`, asserting status 0 and output containing `Usage:`; and `script with no args exits 1`.
- [ ] **Step 2: Run** `bats tests/reassess/smoke.bats`. Expected: FAIL, script missing.
- [ ] **Step 3: Implement** the executable script skeleton with `set -euo pipefail`, a `usage` function, and the exit-code constants from Global Constraints. Add `just test` as `bats tests/reassess`.
- [ ] **Step 4: Run** `just test`. Expected: PASS.
- [ ] **Step 5: Add hooks** `shellcheck` and `shfmt` to `.pre-commit-config.yaml` (frozen SHAs with version comments, matching the existing style), scoped to `jmeridth-skills/skills/reassess/scripts/` and `tests/`. Run `just precommit`. Expected: PASS.
- [ ] **Step 6: Add `.github/workflows/test.yaml`** on `pull_request`: harden-runner, checkout (`persist-credentials: false`), install `bats` (apt), run `just test`. Pin every action by SHA, copying the SHAs used in `pre-commit.yaml`. Run `just precommit` (actionlint). Expected: PASS.
- [ ] **Step 7: Commit** via the `commit` skill.

### Task 2: Config loading and validation

**Files:**

- Modify: `jmeridth-skills/skills/reassess/scripts/reassess-candidates`
- Create: `tests/reassess/config.bats`, `tests/reassess/fixtures/config-*.yaml`

**Interfaces:**

- Consumes: Task 1 skeleton and `setup_stub`.
- Produces: `load_config <path>` prints normalized JSON `{"default_clone_path":"/abs","monitor":[{"kind":"org","org":"o","exclude":["a"]},{"kind":"repo","repo":"o/r","path":"/abs-or-null"}]}` with `~` expanded and trailing slashes stripped. `--dump-config --config PATH` prints it.
- Produces: on failure, print the expected schema to stderr and exit 2.

- [ ] **Step 1: Write failing tests**, one per case, each asserting status and (for failures) that stderr contains `monitor:`: `valid config normalizes tilde and trailing slash`, `missing file exits 2`, `invalid yaml exits 2`, `empty monitor exits 2`, `entry with both org and repo exits 2`, `repo without slash exits 2`, `exclude must be a list of names`, `yq is not mikefarah v4 exits 2 with message`. Also `single-repo mode does not invoke yq` (put a failing `yq` first on `PATH`; run `reassess-candidates o/r` with the stub; assert it does not fail on yq).
- [ ] **Step 2: Run** `bats tests/reassess/config.bats`. Expected: FAIL.
- [ ] **Step 3: Implement `load_config`** with `yq -o=json` piped to `jq` for validation and normalization. Check `yq --version` for `mikefarah` and `v4` only in config mode.
- [ ] **Step 4: Run** `just test`. Expected: PASS.
- [ ] **Step 5: Commit** via the `commit` skill.

### Task 3: Search and candidate discovery

**Files:**

- Modify: `reassess-candidates`
- Create: `tests/reassess/search.bats`, `tests/reassess/fixtures/search-*.json`

**Interfaces:**

- Consumes: `load_config`; stub `gh`.
- Produces: `build_queries <normalized-config-json> <login>` prints one JSON array of `{"role":"review-requested|author|reviewed-by|commenter","scope":"org:o"|"repo:a repo:b …","args":[...]}`. Org entries yield four queries each. Repo entries are chunked, at most 10 `repo:` qualifiers per query, four roles per chunk. Every query includes `--state open` and `archived:false`.
- Produces: `discover <queries-json>` prints a deduped JSON array of `{repo,number,title,author,isDraft,updatedAt,roles[]}`. It drops archived repos (client-side check on `repository.isArchived`), org-excluded repos (unless an explicit `repo` entry names them), and drafts authored by others. Dedupe key is lowercase `owner/name#number`.
- Produces: if a search returns 1000 results, record `{"query": ...}` in `truncated`. A rate-limit error exits 3 and prints nothing to stdout.
- Produces: `gh auth status` failure exits 4 before any search.

- [ ] **Step 1: Write failing tests**: `org entry builds four queries with org qualifier`, `repo entries chunk at 10`, `queries exclude archived`, `exclude drops repo`, `explicit repo beats org exclude`, `dedupes mixed-case repo names`, `drops others' drafts but keeps mine`, `zero results gives empty prs and exit 0`, `1000 results sets truncated`, `rate limit exits 3 with empty stdout` (use `GH_STUB_FAIL_MATCH`), `unauthenticated exits 4`.
- [ ] **Step 2: Run** `bats tests/reassess/search.bats`. Expected: FAIL.
- [ ] **Step 3: Implement `build_queries` and `discover`**. Use `gh search prs --json repository,number,title,author,isDraft,updatedAt --limit 1000`. The `roles` field records which searches matched.
- [ ] **Step 4: Run** `just test`. Expected: PASS.
- [ ] **Step 5: Commit** via the `commit` skill.

### Task 4: Classification and draft candidates

**Files:**

- Modify: `reassess-candidates`
- Create: `tests/reassess/classify.bats`, `tests/reassess/fixtures/pr-*.json`

**Interfaces:**

- Consumes: `discover` output and the login.
- Produces: `classify <pr-json> <login> <now-utc>` prints the PR row from the output contract. It fetches per-PR detail only for these candidates (`gh pr view --json comments,reviews,commits`, `gh api repos/{o}/{r}/pulls/{n}/comments`, `gh pr checks --required` for non-draft PRs by others).
- Produces: top-level assembly prints the full output object. `prs` is sorted by bucket (A, B, C, null) then `updatedAt` descending.

Rules to implement (copied from the current `SKILL.md` steps 4 and 4.5, now owned by the script):

- A: I authored it, and the newest non-bot, non-resolved activity by someone else is later than my last commit or comment. Logins ending `[bot]` are ignored, except a bot review with inline comments is kept and noted in `reasons` for the agent.
- B: someone else authored it, I reviewed or commented, and the head commit time is later than my newest review or comment time. A prior approval is noted in `reasons`.
- C: someone else authored it, non-draft, and I left no review or comment (explicit `review-requested` or not).
- Draft candidate: non-draft, not mine, and either `gh pr checks --required` reports a failure, or I have reviewed and the PR has no author activity for 7 days after my latest review.

- [ ] **Step 1: Write failing tests** with fixture PRs: `bucket A when other's comment is newer than my push`, `resolved thread does not count`, `bot comment ignored`, `bot review with inline comments kept and noted`, `bucket B when head commit newer than my review`, `equal timestamps are not stale`, `approval noted in reasons`, `commenter-only candidate uses comment time`, `bucket C for review-requested`, `bucket C for unreviewed open PR`, `A beats B beats C`, `my PR in author, reviewed-by, commenter searches yields one row in A`, `draft candidate on failing required check`, `draft candidate after 7 days`, `no draft flag on my PRs or drafts`, `required-checks error skips flag and notes reasons`, `sort order`.
- [ ] **Step 2: Run** `bats tests/reassess/classify.bats`. Expected: FAIL.
- [ ] **Step 3: Implement `classify`** with `jq`, comparing UTC ISO strings lexicographically. Take `now` from `date -u` and allow an override via `REASSESS_NOW` for tests.
- [ ] **Step 4: Run** `just test`. Expected: PASS.
- [ ] **Step 5: Commit** via the `commit` skill.

### Task 5: Clone path and sync

**Files:**

- Modify: `reassess-candidates`
- Create: `tests/reassess/sync.bats`

**Interfaces:**

- Consumes: normalized config, set of repos from `discover`.
- Produces: `sync_repo <owner/name> <clone-path>` prints `{"repo","status","reason"}` and also sets `clone_path` on each PR row. Statuses and reasons: `synced`; `skipped` with `no clone`, `dirty tree`, `not on default branch`, `diverged`, or `pull failed`. Default branch comes from `git symbolic-ref refs/remotes/origin/HEAD`, falling back to `gh repo view --json defaultBranchRef`.
- Single-repo mode with no config syncs the current directory's repo only if it is a clone of that repo.

- [ ] **Step 1: Write failing tests** using real temp git repos (a bare "origin" and a clone): `clean default branch fast-forwards`, `missing clone is skipped with reason`, `dirty tree is skipped and left untouched`, `non-default branch is skipped and not switched`, `diverged is skipped`, `path override beats default_clone_path`, `fallback to gh for default branch`.
- [ ] **Step 2: Run** `bats tests/reassess/sync.bats`. Expected: FAIL.
- [ ] **Step 3: Implement `sync_repo`** with `git -C`, `git fetch`, `git status --porcelain`, and `git pull --ff-only`. Never stash, switch, or reset.
- [ ] **Step 4: Run** `just test`. Expected: PASS.
- [ ] **Step 5: Commit** via the `commit` skill.

### Task 6: `SKILL.md`, version bump, docs

**Files:**

- Modify: `jmeridth-skills/skills/reassess/SKILL.md`, `jmeridth-skills/.claude-plugin/plugin.json`, `README.md` if it lists skill behavior

**Interfaces:**

- Consumes: the script CLI and output contract.

- [ ] **Step 1: Edit `SKILL.md`**: update `argument-hint` to `[owner/repo | refresh]`. Add the `refresh` argument and config path. Replace steps 0 (sync), 3, 4, and 4.5 with a call to `"${CLAUDE_PLUGIN_ROOT}/skills/reassess/scripts/reassess-candidates"` (`owner/repo` or `--config ~/.config/jmeridth-skills/config.yaml`). Keep step 5 (report, add a `Repo` column in `refresh` mode, report `sync` skips and `truncated`), step 6, and all Rules. Add the provenance guard and bot-review judgment as explicit agent steps using `raw` and `reasons`. Add one sentence that `/loop` or `/schedule` can wrap `refresh` later. Keep the first line of the sync audit rule: the script run is the first action.
- [ ] **Step 2: Bump `plugin.json`** to the next free version above `origin/main`.
- [ ] **Step 3: Run** `just precommit` and `just test`. Expected: PASS.
- [ ] **Step 4: Invoke the `skill-authoring` skill** to validate `SKILL.md` against the agentskills.io rules. Fix findings.
- [ ] **Step 5: Commit** via the `commit` skill.

### Task 7: Live dry run, PR, ruleset

- [ ] **Step 1: Dry run.** Create a throwaway config at a temp path with one real org of Jason's. Run the script with `--config`. Check: valid JSON, no archived repos, nothing posted or changed, search calls under the rate limit. Run `/reassess` on this repo and confirm unchanged behavior.
- [ ] **Step 2: Open a draft PR** through the `pr` skill. Confirm `pre-commit`, `version-check`, and `test` pass.
- [ ] **Step 3: Ruleset.** Show Jason the `gh api` command that adds `test` to the `main` ruleset's required checks. Run it only after he confirms.
- [ ] **Step 4: Write the handoff** to `~/.claude/handoffs/skills/2026-10-31-reassess-multi-repo.md`.
