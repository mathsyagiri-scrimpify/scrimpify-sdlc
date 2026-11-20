# scrimpify-sdlc v0.1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `scrimpify-sdlc` Claude Code plugin (standard, 22 skills, 2 agents, 6 hooks, lane/CI scripts, templates) in `D:\Projects\scrimpify-sdlc`, so developers and QA in an adopting monorepo work independently.

**Architecture:** The repo is a plugin marketplace holding one plugin in `plugin/`. Enforcement = bash hooks sharing `plugin/hooks/lib.sh` and a lane library `plugin/scripts/lanes.sh` that the hooks, CI check scripts and generators all use. Behaviour = markdown skills, agent definitions and review briefs. A bash test suite drives every hook with JSON payloads and every script with fixture repos.

**Tech Stack:** Claude Code 2.1.x plugins, bash 5 + git + sed/awk/grep (Git Bash on Windows), GitHub Actions, `gh`.

**Spec:** `docs/design.md` (v2, approved 2026-11-20). Read it before any task; § numbers refer to it.

## Global Constraints

- **Clean room:** write every file fresh. Do not open any other organisation's plugin files (nothing under `C:\Users\*\.claude\plugins\` or `E:\`). The repo must not contain the names of any other organisation or its tooling (case-insensitive); Task 16 tests it with a list the controller supplies.
- Under `plugin/`: bash, git, sed, awk, grep, tr, cut, sort, head, find, mktemp only. **No jq, python, node.** Tests may use `python` only to validate JSON.
- LF endings for `*.sh`, `*.md`, `*.json`, `*.yml` (`.gitattributes`).
- Plugin and marketplace name `scrimpify-sdlc`; version `0.1.0` in `plugin/VERSION` and `plugin/.claude-plugin/plugin.json`; repository `https://github.com/mathsyagiri-scrimpify/scrimpify-sdlc`.
- The 22 skill names exactly: `shape`, `decompose`, `design-feature`, `review-design`, `file-issues`, `create-issue`, `change-request`, `change-contract`, `pick-up`, `build`, `verify`, `open-pr`, `fix-review`, `update-issue`, `investigate`, `build-feature`, `verify-feature`, `write-test-cases`, `qa-browser`, `review-ui`, `record-run`, `file-bug`. Agents: `reviewer`, `task-builder`.
- Protected branches: `main`, `master`, the repo's `origin/HEAD` default. Branch forms: `<issue>-<slug>`, `docs/<slug>`, `contract/<slug>`.
- Commit trailers: `Co-Authored-By: Claude <model> <noreply@anthropic.com>` and `Scrimpify-SDLC: v0.1.0`.
- `plugin/STANDARD.md` ≤ 8192 bytes.
- PreToolUse decision output: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny|ask","permissionDecisionReason":"…"}}`, exit 0. Allow = exit 0, no output. Unparseable input = exit 0, no output.
- A payload is from a **subagent** when it carries a non-empty `agent_id` (Task 2 confirms the field name on Claude Code 2.1.x; if it differs, change only `sdlc_is_subagent`).

### Repo file formats (pinned here; skills, hooks and scripts all rely on them)

**Feature frontmatter** — `docs/features/fNN-<slug>/requirements.md`:
```yaml
---
id: F03
name: inventory
owner: <github-login>
status: planned            # planned | active | complete
depends_on: [F00, F01]
contracts: [inventory-catalog]
owns:
  - src/Modules/Inventory/Features/Products/
  - web/apps/admin/src/features/products/
  - tests/e2e/products/
---
```
`owns:` entries are **directory prefixes ending in `/`** or exact file paths; no wildcards. Ownership counts only while `status` is `planned` or `active`.

**Path classes** — `docs/sdlc/paths.txt`, one rule per line, `#` comments:
```
add-only  src/Cowos.Api/Registrations/
add-only  web/apps/admin/src/routes/
guarded   docs/contracts/
generated web/packages/api-client/
```
Longest matching prefix wins. A path matching nothing and owned by no active feature is `unowned` (treated as guarded).

**Task list** — `tasks.md`: `- [ ] T001 [ready:agent] Title` with an optional ` #41` at the end once filed; `- [x]` = done. **Task body** — `bodies/T001.md` has lines `Depends on: T000, …` (or `none`) and criteria as `- AC1: …`.

**plan.md header** (first lines): `Issue: <owner>/<repo>#41` · `Feature: F03` · `Task: T002` · `Branch: 41-product-pricing`. **Tests table rows:** `| #41/AC1 | <test name> | <layer> | <file> |` or `| #41/AC2 | test gap: <reason> | | |`. Tests carry `#41/AC1` in their name or a tag/comment. **Review** section ends with `Result: PASS` or `Result: FAIL`.

**build.md** — sections `## Tasks` (table `| Task | Issue | Depends on | State | Branch | Worktree |`, states `queued|planning|waiting-decision|building|verifying|done|failed`), `## Waiting on you`, `## Push gate`, `## Milestones`, `## Log`.

**Generated blocks** — between `<!-- generated:<name> -->` and `<!-- /generated:<name> -->` in `docs/product/roadmap.md` (`features`) and `docs/product/test-plan.md` (`coverage`). Nothing else in those files is touched by generators.

## Review Focus

1. **Windows paths in payloads** (`D:\\Projects\\Cowos\\src\\a.cs`, `D:/Projects/...`, `/d/Projects/...`): `guard-branch` and `guard-scope` resolve the repo and the repo-relative path for all three. Tests in Tasks 3 and 6.
2. **Prefix look-alikes:** owner prefix `src/Modules/Inventory/` must not claim `src/Modules/Inventory2/x.cs`; `add-only web/apps/admin/src/routes/` must not cover `web/apps/admin/src/routes-old/`. Tests in Task 6.
3. **Subagent vs main session:** the same command must be `ask` for the main session and `deny` for a subagent; a wrong split either blocks the developer or lets a subagent push. Tests in Tasks 4–6.
4. **Compound, wrapped and quoted commands** (`cd x && git push origin main`, `git -C ../r push`, `env A=1 git push`, newline or `;` separated; `git commit -m "document git push --force"` must pass). Tests in Task 4.
5. **Empty or malformed stdin** to every hook: exit 0, no output. Tests in Tasks 2–6.

---

## File structure

```
scrimpify-sdlc/
├── .claude-plugin/marketplace.json
├── .gitattributes .gitignore README.md CHANGELOG.md
├── .github/workflows/ci.yml
├── docs/design.md  docs/superpowers/plans/…
├── plugin/
│   ├── .claude-plugin/plugin.json   VERSION   STANDARD.md
│   ├── hooks/      hooks.json lib.sh session-start.sh check-update.sh guard-branch.sh
│   │               guard-git.sh guard-shared.sh guard-rails.sh guard-scope.sh
│   ├── scripts/    lanes.sh gen-codeowners.sh gen-tables.sh
│   │               check-review-record.sh check-owns-overlap.sh check-add-only.sh
│   │               check-lane.sh check-criteria-coverage.sh check-todo-issue.sh check-tests-changed.sh
│   ├── agents/     reviewer.md task-builder.md
│   ├── reviews/    plan.md design.md bite.md fix.md feature-design.md feature.md
│   ├── skills/<22>/SKILL.md
│   ├── templates/  feature-requirements.md feature-design.md decisions.md tasks.md task-body.md
│   │               plan.md build.md contract.md roadmap.md master-test-plan.md feature-test-plan.md
│   │               run.yaml bug-issue.md task-issue.md pr-body.md pr-body-docs.md paths.txt
│   │               claude-md-section.md
│   ├── checklists/ api-contract.md react-ui.md
│   └── ci/         workflow-dotnet-react-monorepo.yml
└── tests/          lib.sh run.sh repo.sh hooks-*.sh scripts-*.sh version-guard.sh fixtures.sh
```

---

### Task 1: Repo skeleton, manifests, test harness

**Files:** Create `.claude-plugin/marketplace.json`, `plugin/.claude-plugin/plugin.json`, `plugin/VERSION`, `.gitattributes`, `.gitignore`, `README.md` (stub), `CHANGELOG.md` (`## 0.1.0 — unreleased`), `tests/lib.sh`, `tests/run.sh`, `tests/repo.sh`, `tests/fixtures.sh`. Delete the superseded `docs/superpowers/plans/2026-11-16-scrimpify-sdlc-v0.1.md`.

**Interfaces — Produces:**
- `tests/lib.sh`: `pass <msg>`, `fail <msg>`, `expect_eq <actual> <expected> <msg>`, `expect_contains <haystack> <needle> <msg>`, `refute_contains <haystack> <needle> <msg>` (**fails when the haystack is empty**), `expect_empty <value> <msg>`, `finish` (exit 1 if any failure or zero passes).
- `tests/fixtures.sh`: `make_repo <dir> <branch>` (git init, one commit, branch checked out); `make_cowos_like <dir>` (a repo with `docs/features/f00-foundation/requirements.md` status complete, `f03-inventory` owning `src/Modules/Inventory/Features/Products/`, `f05-booking` owning `src/Modules/Booking/Features/Checkout/`, both `active`; a `docs/sdlc/paths.txt` with one `add-only`, one `guarded`, one `generated` rule; a `docs/work/2026/41-product-pricing/plan.md` with header `Feature: F03`).
- `tests/run.sh`: runs every `tests/*.sh` except `lib.sh`, `run.sh`, `fixtures.sh` in its own subshell; sums; non-zero on any failure.

- [ ] **Step 1:** `git init -b main` in `D:\Projects\scrimpify-sdlc`; empty initial commit; `git checkout -b build/v0.1.0`.
- [ ] **Step 2: Write `tests/repo.sh`:** VERSION equals plugin.json version; marketplace has one plugin `scrimpify-sdlc` with source `./plugin`; `refute_contains "" x` is counted as a failure (harness self-test).
- [ ] **Step 3: Run** `bash tests/run.sh` → FAIL.
- [ ] **Step 4: Create** manifests, `.gitattributes` (`* text=auto eol=lf`, `*.pdf binary`, `*.png binary`), harness, fixtures.
- [ ] **Step 5: Run** `bash tests/run.sh` → PASS; `claude plugin validate plugin` and `claude plugin validate .` → no errors.
- [ ] **Step 6: Commit** `chore: skeleton, manifests, test harness` (includes `docs/`).

### Task 2: Hook library, standard, session start

**Files:** Create `plugin/hooks/lib.sh`, `plugin/STANDARD.md`, `plugin/hooks/session-start.sh`, `plugin/hooks/check-update.sh`, `tests/hooks-session.sh`

**Interfaces — Produces (`lib.sh`):**
- `sdlc_read_payload` → sets `SDLC_PAYLOAD` (stdin, newlines removed); returns 1 if empty.
- `sdlc_json_str <key>` → first string value of `"<key>":"…"`, unescaping `\"` and `\\`.
- `sdlc_json_escape` (stdin → JSON-safe string; newline → `\n`, CR dropped).
- `sdlc_decide <deny|ask> <reason>`.
- `sdlc_is_subagent` → 0 when `agent_id` is non-empty.
- `sdlc_to_posix_path <path>` (`D:\a\b`, `D:/a/b` → `/d/a/b`).
- `sdlc_repo_of <path>` → repo top level of the nearest existing ancestor dir, or empty.
- `sdlc_rel_path <repo> <abs-path>` → path relative to the repo.
- `sdlc_branch <repo>` → current branch, empty if detached/none.
- `sdlc_protected <repo>` → protected branch names, one per line.
- `session-start.sh` → `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}` with `scrimpify-sdlc v<VERSION> is active in this repo. Plugin files: <CLAUDE_PLUGIN_ROOT>.`, a blank line, then `STANDARD.md`.
- `check-update.sh` → remote from `SCRIMPIFY_SDLC_REMOTE` (default the repo URL + `.git`), `GIT_TERMINAL_PROMPT=0 git ls-remote --tags`; prints `scrimpify-sdlc v<new> is available (installed v<cur>): run claude plugin update scrimpify-sdlc@scrimpify-sdlc`, or nothing when current, or `scrimpify-sdlc update check failed: <reason>`.

- [ ] **Step 1: Confirm the subagent field.** Write a throwaway hook in a scratch repo that appends its stdin to a file, run `claude -p` with a prompt that dispatches a subagent which runs `echo hi`; read the logged payloads; note the field that distinguishes the subagent call. Record it in `CHANGELOG.md` under 0.1.0 "Verified". Delete the scratch repo.
- [ ] **Step 2: Write tests** (`tests/hooks-session.sh`): STANDARD.md ≤ 8192 bytes and contains the headings `Understand before acting`, `Issue first`, `Plan, approve, build`, `Tests first`, `Review before PR`, `Nothing outward without a yes`, `Never on main`, `Stay in your lane`, `Stay in scope`, `Data and secrets`, `Honest reporting`, `Ask well`, `Keep artifacts current`, `Repo rules win`, `Resume from files`, `Ends at merge`; session-start output parses as JSON and contains the version; check-update with a local bare remote tagged `v0.1.0` → empty, tagged `v0.2.0` → `v0.2.0 is available`, missing remote → `update check failed`; `sdlc_to_posix_path 'D:\Projects\x'` → `/d/Projects/x`; `sdlc_json_str command` on `{"tool_input":{"command":"echo \"hi\""}}` → `echo "hi"`; `sdlc_is_subagent` true/false on payloads with/without the field; empty stdin → exit 0, no output.
- [ ] **Step 3: Run** → FAIL. **Step 4:** Write `STANDARD.md` (design §8, each point under the heading above; under `Stay in your lane` also design §3 item 7: the breaker fixes it, anyone may revert the merge that turned `main` red, flaky tests are quarantined with an issue to their owner; plus trailers and the skill list by role, one line each) and implement the scripts. **Step 5: Run** → PASS.
- [ ] **Step 6: Commit** `feat: hook library, standard, session start, update check`.

### Task 3: guard-branch

**Files:** Create `plugin/hooks/guard-branch.sh`, `tests/hooks-branch.sh`

- [ ] **Step 1: Write tests** (Write payloads): repo on `main` → deny; reason contains `protected branch 'main'`, `<issue>-<slug>`, `docs/<slug>`, `contract/<slug>`, `never invent an issue number`; on `master` → deny; on the `origin/HEAD` default (`trunk` in the fixture) → deny; on `41-x`, `docs/x`, `claude/brave-otter` → allow; with local branches `12-a` and `docs/x` → reason lists both; **Review Focus 1:** the same file in `D:\\…`, `D:/…`, `/d/…` forms (built from `pwd -W`; drive forms skipped on Linux) → deny on `main`; outside any repo → allow; new file in a missing subfolder of a `main` repo → deny; detached HEAD → allow; unborn branch → allow; empty and `not json` stdin → exit 0, no output.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Commit** `feat: guard-branch`.

### Task 4: guard-git

**Files:** Create `plugin/hooks/guard-git.sh`, `tests/hooks-git.sh`; add `sdlc_segments` to `lib.sh`

**Interfaces — Produces:** `sdlc_segments <command>` → one segment per line after blanking quoted strings (`'…'`, `"…"` → `""`) and splitting on `&&`, `||`, `;`, `|`, newline; strips leading `env`, `VAR=value`, `sudo`, `command`. Also `sdlc_git_target <segment> <cwd>` → the repo dir a git segment acts on (`-C <path>` or the cwd).

- [ ] **Step 1: Write tests**, main session / subagent:

| Command | Main | Subagent |
|---|---|---|
| `git push origin main` | deny | deny |
| `git push origin HEAD:main` | deny | deny |
| `git push --force origin 41-x` / `git push -f` / `git push origin +41-x` | deny | deny |
| `git push --force-with-lease origin 41-x` | ask | deny |
| `git push -u origin 41-x` | ask | deny |
| `git commit -m x` on `main` | deny | deny |
| `git commit -m x` on `41-x` | allow | allow |
| `git commit --no-verify -m x` | deny | deny |
| `gh pr create --fill` / `gh pr merge 5` / `gh pr comment 5 -b x` | ask | deny |
| `gh issue create -t x -b y` / `gh issue comment 41 -b x` / `gh issue edit 41` | ask | deny |
| `gh label create x` / `gh api repos/o/r/issues -f title=x` / `gh api -X PATCH repos/o/r/issues/1` | ask | deny |
| `gh api graphql -f query='mutation{x}'` | ask | deny |
| `gh issue view 41` / `gh pr view 5 --comments` / `gh pr checks 5` / `gh api repos/o/r/issues/1` / `gh api graphql -f query='query{viewer{login}}'` | allow | allow |
| `cd ../r && git push origin main` / `git -C ../r push origin main` | deny | deny |
| `env GIT_TRACE=1 git push -u origin 41-x` | ask | deny |
| `git status`↵`git push origin main` · `git add .; git push origin main` (PowerShell) | deny | deny |
| `git commit -m "document git push --force"` on `41-x` · `echo "gh pr create"` · `git log` | allow | allow |

  Plus empty/malformed stdin → exit 0, no output. Deny reasons name the rule; subagent denials say `subagents never push or write to GitHub; return your result to the orchestrator`. Ask reasons start `Outward action:` and quote the segment.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (GraphQL: read `query=` from the raw segment; `mutation` → write). **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: guard-git`.

### Task 5: guard-shared and guard-rails

**Files:** Create `plugin/hooks/guard-shared.sh`, `plugin/hooks/guard-rails.sh`, `tests/hooks-shared.sh`, `tests/hooks-rails.sh`

- [ ] **Step 1: Write tests.**
  - **guard-shared** (subagent → deny, main → allow): `git stash`, `git stash pop`, `git worktree remove x`, `git worktree prune`, `docker system prune -f`, `docker volume prune`, `docker image prune -a`, `docker rm -f $(docker ps -aq)`, `taskkill /IM node.exe /F`, `pkill node`, `killall dotnet`, `Stop-Process -Name node`, `winget install x`, `choco install x`, `npm install -g x`, `dotnet tool install -g x`, `rm -rf "$CLAUDE_SCRATCHPAD"` (when that variable is set). Allowed for subagents: `docker rm cowos-pg-41`, `kill 1234`, `npm install`, `dotnet restore`.
  - **guard-rails:** Read deny `~/.ssh/id_ed25519`, `$HOME/.aws/credentials`, `C:\\Users\\u\\.aws\\sso\\cache\\x.json`, `~/.config/gh/hosts.yml`, `C:\\Users\\u\\AppData\\Roaming\\GitHub CLI\\hosts.yml`, `certs/site.pem`, `a.key`, `b.pfx`, `.env`, `web/apps/admin/.env.local`; Read allow `.env.example`, `.env.sample`, `src/Keyboard.cs`; Bash deny `cat ~/.aws/credentials`, PowerShell `Get-Content $HOME\.ssh\id_rsa`; Edit deny `~/.bashrc`, `~/.profile`, `~/.gitconfig`, `~/.config/git/config`, `~/.config/gh/config.yml`; ask `terraform apply`, `terraform -chdir=infra apply -auto-approve`, `terragrunt destroy`, `aws s3 rm s3://x --recursive`, `aws ec2 terminate-instances --instance-ids i-1`, `aws rds delete-db-instance --db-instance-identifier x`, `aws ssm put-parameter --name x`, `aws --profile cowos-prod s3 ls`; allow `terraform plan`, `terraform validate`, `aws s3 ls`, `aws sts get-caller-identity`. Empty/malformed stdin → exit 0, no output, for both hooks.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (AWS write = `aws <service> <op>` with op starting `create|delete|put|update|terminate|modify|rm|mv|cp|sync|run|start|stop|reboot|attach|detach|send|invoke`; production = `prod` in a `--profile` value or a host). **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: guard-shared and guard-rails`.

### Task 6: Lane library and guard-scope

**Files:** Create `plugin/scripts/lanes.sh`, `plugin/hooks/guard-scope.sh`, `tests/hooks-scope.sh`, `tests/scripts-lanes.sh`

**Interfaces — Produces (`lanes.sh`, sourced by hooks, CI scripts and generators):**
- `lanes_active_owns <repo>` → `F03<TAB>owner<TAB>prefix` per owned prefix of every `planned`/`active` feature.
- `lanes_class <repo> <rel-path>` → one of `owned F03 <owner>`, `add-only`, `guarded`, `generated`, `work` (under `docs/work/`), `unowned`. An owned prefix beats a `paths.txt` rule only when longer.
- `lanes_feature_of_branch <repo>` → the `Feature:` value of the `docs/work/*/<branch>/plan.md` whose `Branch:` matches the current branch; empty if none.
- `lanes_task_dir_of_branch <repo>` → that plan's folder (relative).

guard-scope behaviour: no current feature → allow. Allowed: own `owned`, `add-only`, `work` inside its own task dir. `generated` → deny for everyone (`generated file; change its source instead`). Other `owned`, `guarded`, `unowned` → ask (main) naming the owner (`this is F05's lane (owner @x); the PR will need their approval`) or `shared path; use /scrimpify-sdlc:change-contract`; deny for a subagent.

- [ ] **Step 1: Write tests** with `make_cowos_like`, on branch `41-product-pricing` (F03): edit `src/Modules/Inventory/Features/Products/Price.cs` → allow; `src/Modules/Booking/Features/Checkout/Pay.cs` → ask (main, reason names F05 and its owner), deny (subagent); the add-only path → allow; `docs/contracts/x.md` → ask/deny with `change-contract`; generated path → deny; own `docs/work/2026/41-product-pricing/plan.md` → allow; **Review Focus 2:** `src/Modules/Inventory/Features/Products2/x.cs` → not owned by F03 (ask); a `routes-old/` sibling of the add-only `routes/` → not add-only; F00 (`complete`) owns nothing; **Review Focus 1:** the same file as `D:\\…`, `D:/…` and `/d/…` → same results; branch with no plan → allow; empty stdin → exit 0, no output. `lanes_class` unit tests for each class.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: lane library and guard-scope`.

### Task 7: Hook wiring

**Files:** Create `plugin/hooks/hooks.json`; add to `tests/repo.sh`

- [ ] **Step 1: Write test:** every script in `hooks.json` exists and every hook script is wired; commands are `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`; matchers: SessionStart `startup|resume|clear|compact` → session-start; SessionStart `startup` → check-update; PreToolUse `Write|Edit|MultiEdit|NotebookEdit` → guard-branch, guard-scope; `Bash|PowerShell` → guard-git, guard-shared; `Bash|PowerShell|Read|Grep|Glob|Edit|Write|MultiEdit|NotebookEdit` → guard-rails.
- [ ] **Step 2: Run** → FAIL. **Step 3: Write** `hooks.json`. **Step 4: Run** + `claude plugin validate plugin` → PASS. **Step 5: Commit** `feat: wire hooks`.

### Task 8: Generators and lane CI checks

**Files:** Create `plugin/scripts/gen-codeowners.sh`, `gen-tables.sh`, `check-owns-overlap.sh`, `check-add-only.sh`, `check-lane.sh`, `tests/scripts-lanes-ci.sh`

**Interfaces — Produces** (all take the repo as cwd; check scripts take `BASE` (default `origin/main`) and `HEAD`):
- `gen-codeowners.sh [--check]` → writes `.github/CODEOWNERS`: a header comment `# generated by scrimpify-sdlc from docs/features/*/requirements.md; do not edit`, then `/<prefix> @<owner>` per active owned prefix, sorted. `--check` exits 1 with a diff if the file differs.
- `gen-tables.sh [--check]` → fills the `features` block of `docs/product/roadmap.md` (`| Feature | Owner | Status | Depends on | Tasks done |`, tasks done = `[x]` count / total in `tasks.md`) and the `coverage` block of `docs/product/test-plan.md` (`| Feature | Cases | Automated | Manual | Last run | Result |` from each feature's `test-plan.md` and the newest `docs/test-runs/*.yaml` naming it). `--check` exits 1 if stale.
- `check-owns-overlap.sh` → exit 1 listing pairs of active features where one prefix starts with another; also runs `gen-codeowners.sh --check`.
- `check-add-only.sh` → exit 1 listing each modified or deleted line (`git diff -U0` `-` lines) under an `add-only` path.
- `check-lane.sh` → prints each changed path with its `lanes_class`; always exit 0 (code-owner review is what blocks). Exit 1 only for changes under `generated` paths.

- [ ] **Step 1: Write tests** with fixtures: CODEOWNERS generated as expected and `--check` passes, then fails after editing a feature's `owns:`; two active features with `src/Modules/Inventory/` and `src/Modules/Inventory/Features/` → overlap failure; a complete feature with the same prefix → no failure; gen-tables writes only between markers (text outside unchanged) and `--check` detects staleness; add-only diff that only adds → pass, that edits a line → fail; lane report lists classes, generated change → exit 1.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Step 5: Commit** `feat: CODEOWNERS and table generators, lane CI checks`.

### Task 9: PR CI checks and workflow template

**Files:** Create `plugin/scripts/check-review-record.sh`, `check-criteria-coverage.sh`, `check-todo-issue.sh`, `check-tests-changed.sh`, `plugin/ci/workflow-dotnet-react-monorepo.yml`, `tests/scripts-pr-ci.sh`

**Interfaces:**
- `check-review-record.sh` → docs-only diff: prints `skipped: docs-only change`, exit 0. Else: the changed `docs/work/*/*/plan.md` must exist, contain `## Review`, and its last `Result:` line be `Result: PASS`; else exit 1 with the reason.
- `check-criteria-coverage.sh` → for that plan: every `#N/AC<k>` row is either `test gap: <non-empty reason>` or names a file in the diff or repo that contains the id; exit 1 listing uncovered ids.
- `check-todo-issue.sh` → exit 1 for each added line containing `TODO` without `#<digits>`.
- `check-tests-changed.sh` → warning per area (`src/Modules/<M>/`, `web/apps/<app>/`, `web/packages/<pkg>/`, `renderer/`) with source changes and no test-file changes; always exit 0.

- [ ] **Step 1: Write tests** with fixtures: docs-only → skipped exit 0; code without plan → 1; `Result: FAIL` → 1; `Result: PASS` → 0; criterion row pointing at a file containing `#41/AC1` → 0, at a file without it → 1, `test gap:` with empty reason → 1; bare `TODO` → 1, `TODO(#41)` → 0; untested source → warning, exit 0.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** scripts and the workflow template: jobs `unit-integration` (`dotnet test` on the whole solution with Testcontainers; skipped with a printed notice when no `.sln` exists yet), `web` (pnpm workspace test), `sdlc-checks` (all eight check scripts plus `gen-tables.sh --check`), docs-only PRs run only `sdlc-checks`; a header comment telling the adopter to adjust paths to the real layout and to mark jobs required. **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: PR CI checks and workflow template`.

### Task 10: Agents and review briefs

**Files:** Create `plugin/agents/reviewer.md`, `plugin/agents/task-builder.md`, `plugin/reviews/{plan,design,bite,fix,feature-design,feature}.md`

**Interfaces — Produces:**
- Reviewer contract: spawned with (a) brief path, (b) material paths, (c) applicable `docs/sdlc/checklists/*.md`. Output's first line is exactly `VERDICT: PASS` or `VERDICT: FAIL`; findings `- [blocking|note] <file>:<line> — <what> — <evidence>`.
- Task-builder contract: input = feature folder, task id, issue ref, worktree path, branch, base branch, any decisions already settled. Output's first line `RESULT: done|waiting-decision|failed`, then `Branch:`, `Commits:` (short shas), `Review: PASS|FAIL`, `Decisions open:` (list), `Notes:`. It works only inside its worktree, follows `pick-up`/`build`/`verify` without the human plan stop, commits locally, never pushes or posts.

- [ ] **Step 1:** Write `reviewer.md` (tools: Read, Grep, Glob, Bash; adversarial; never saw the conversation; never edits the working tree; bite work happens in a `mktemp -d` copy) and `task-builder.md` (tools: all; the contract above; the decision rule from design §6.3).
- [ ] **Step 2:** Write the six briefs from design §7.2: `plan` (wrong approach, criterion without test, contract change, out-of-lane steps, size), `design` (diff vs issue/plan/feature design/contracts/checklists; lane violations), `bite` (1–3 mutations per new/changed test on a scratch copy; must go red; remove the copy), `fix` (earlier findings + fix diff only), `feature-design` (three lenses: scope/product fit, architecture/contracts, user experience; overlapping `owns:`, dependency cycles, criteria no task covers, contracts without a provider), `feature` (small: a task vs its neighbours' contracts; full: every criterion and contract of the feature, gaps no task owns).
- [ ] **Step 3: Verify** `claude plugin validate plugin` → no errors. **Commit** `feat: reviewer and task-builder agents, review briefs`.

### Task 11: Templates and example checklists

**Files:** Create every file under `plugin/templates/` listed in File structure, `plugin/checklists/api-contract.md`, `plugin/checklists/react-ui.md`; add a test to `tests/repo.sh`

- [ ] **Step 1: Write test:** every template named in File structure exists and is non-empty; `feature-requirements.md` frontmatter has every key of the pinned format; `plan.md` has the header lines and the sections `## Checked`, `## Approach and steps`, `## Tests`, `## Checklists`, `## Decisions`, `## Size`, `## Risks`, `## Review`; `build.md` has the pinned sections and table header; `roadmap.md` and `master-test-plan.md` contain their generated markers.
- [ ] **Step 2: Run** → FAIL. **Step 3: Write** the templates to the pinned formats; `contract.md` = purpose, provider feature, consumers, kind (endpoint/event/interface/table), the spec, the code locations (interface, fake, contract test), version history; `paths.txt` = commented example rules; `claude-md-section.md` = "Project checks" table (`not configured yet` rows) and skill routing by role. **Step 4: Run** → PASS. **Commit** `feat: templates and example checklists`.

### Task 12: Planning skills

**Files:** Create `plugin/skills/{shape,decompose,design-feature,review-design,file-issues,create-issue,change-request,change-contract}/SKILL.md`; add the 22-skills test to `tests/repo.sh` (each folder has SKILL.md with `name:` equal to the folder and a non-empty `description:`; fails until Task 15)

Each SKILL.md: frontmatter `name` + a `description` saying when to use it; numbered steps; written in your own words from its design row (§6.1) plus the points below. All doc edits happen on a `docs/<slug>` branch and end with `open-pr` docs mode; every GitHub write is listed before running.

- [ ] **Step 1: `shape`** — design §6.1; no code, no issues.
- [ ] **Step 2: `decompose`** — inputs `docs/requirements/` and `docs/designs/`; outputs from templates (`roadmap.md`, `master-test-plan.md`, `requirements.md` per feature, first `docs/contracts/`); F00 first; `depends_on` graph with no cycles; `owns:` left empty on first run (design §10 step 4); `--owns` mode fills every feature's `owns:` in one PR and runs `check-owns-overlap.sh`; `--feature fNN` mode re-generates one feature only and stops (pointing to `change-contract`) if another feature's contract would change; runs `gen-tables.sh`; fresh review with `feature-design` (3 rounds).
- [ ] **Step 3: `design-feature`** — writes `design.md`, `decisions.md`, own contracts, `tasks.md` (readiness, `Depends on` in bodies so independent tasks are visible), `bodies/`; claims `owns:` if missing; names the feature's flag (one flag file in the repo's add-only flags folder, off by default) and makes "add the flag" part of the first task; runs `review-design`; tells QA the feature is ready for test-case pass 1 (does not wait for it).
- [ ] **Step 4: `review-design`**, **`file-issues`** (one preview table `Task | Title | Labels | Readiness | Existing issue | Action`, one yes; refuses `needs-detail`; writes ` #N` onto task lines), **`create-issue`** (`templates/task-issue.md`), **`change-request`** (one feature at a time; lists every affected file/issue before writing; never reverts merged work; contract change → stop, `change-contract`), **`change-contract`** (contract doc + interface + fake + contract test on a `contract/<slug>` branch with a `type:contract` issue; lists every consumer feature and owner from `contracts:` frontmatter; requests their review; reruns `gen-codeowners.sh`).
- [ ] **Step 5: Verify** `claude plugin validate plugin` → no errors. **Commit** `feat: planning skills`.

### Task 13: By-hand build skills

**Files:** Create `plugin/skills/{pick-up,build,verify,open-pr,fix-review,update-issue,investigate}/SKILL.md`

From design §6.2, §6.5, §9, plus:
- [ ] **Step 1: `pick-up`** — `gh issue view <n> --comments` (a failure stops with the error shown); `git fetch origin`; reads the feature folder, contracts, checklists; branch cases from §6.2 (protected → create after approval; `claude/<name>` with no own commits → `git branch -m`; existing → resume; stacked → from the parent task branch); plan from `templates/plan.md` with the pinned header and Tests rows; `plan` reviewer ≤ 2 rounds; plan in full, then one message asking for plan approval and the branch name; on approval commit the plan and post it as an issue comment (listed, hook-prompted).
- [ ] **Step 2: `build`** — criterion loop with the failing output shown; test names carry `#N/AC<k>`; commands from the repo's `CLAUDE.md` "Project checks"; stays in lane (`lanes_class`); stops if a step proves wrong; struck-through steps keep reasons.
- [ ] **Step 3: `verify`** — checks for touched areas ("no checks configured for <area>" when none); `design`, `bite` and `/code-review` in parallel; fixes on the developer's go; `fix` rounds ≤ 3; runs `check-criteria-coverage.sh`, `check-lane.sh`, `check-add-only.sh` locally; writes `## Review` ending `Result: PASS|FAIL`.
- [ ] **Step 4: `open-pr`** — exit list; `check-review-record.sh` must pass; PR from `pr-body.md`; review request only to triggered code owners; one listed yes; own-lane PR offers `gh pr merge --squash` once checks are green (separate yes); docs mode with `pr-body-docs.md`; prints PR link(s).
- [ ] **Step 5: `fix-review`**, **`update-issue`**, **`investigate`** (reproduce with a command and its output; root cause with `path:line`; proposes the fix as a new or existing issue; no code change inside this skill).
- [ ] **Step 6: Verify** validate → no errors. **Commit** `feat: by-hand build skills`.

### Task 14: Orchestrator skills

**Files:** Create `plugin/skills/{build-feature,verify-feature}/SKILL.md`

- [ ] **Step 1: `build-feature <feature>`** — requires the feature's design merged on `main`; runs `file-issues` for unfiled tasks; writes `build.md` from the template (dependency order from bodies, max 3 parallel, stacks, milestones); shows it in full and waits for approval once; for each ready task: `git worktree add ../<repo>-wt/<branch> -b <branch> <base>` then dispatches a `task-builder` subagent with the pinned input, up to the parallel limit; records each RESULT in `build.md`; `waiting-decision` results go to the developer one topic at a time and into `## Waiting on you`; after each `done`, runs `verify-feature small <task>`; at milestones `verify-feature full` and a check-in; push gate lists every branch/PR/comment, sends on one yes (partial allowed); review rounds per PR are their own gate and go back to that task's subagent; resumable from `build.md` (re-reads state, never from memory); removes a task's worktree only after its PR merges.
- [ ] **Step 2: `verify-feature`** — small and full modes per design §6.3 with the `feature` brief; full adds `/code-review` on the feature's combined diff (`git diff origin/main...<tip of each stack>`); ≤ 3 fresh rounds; results into `build.md`.
- [ ] **Step 3: Verify** validate → no errors. **Commit** `feat: orchestrator skills`.

### Task 15: QA skills

**Files:** Create `plugin/skills/{write-test-cases,qa-browser,review-ui,record-run,file-bug}/SKILL.md`

From design §6.4 and §3 (QA independence), plus:
- [ ] **Step 1: `write-test-cases`** — pass 1 / pass 2; `TC-F03-NN`; `Class: Automated (<layer>, <file>) | Manual (<reason>)`; `Priority: Critical|High|Medium|Low`; control case per Critical flow; `Cross-feature: yes|no`; feature `test-plan.md` from template; runs `gen-tables.sh`; own `docs/` PR.
- [ ] **Step 2: `qa-browser`** — runs against `main` with the feature flag on for a QA test tenant (local from QA's clone, or a staging URL given by QA), or `--branch <tip>` in a worktree; uses the repo's Playwright (`npx playwright`) to walk cases, screenshots to `docs/test-runs/<run>/` (gitignored images, record committed); writes the run YAML; drafts bugs.
- [ ] **Step 3: `review-ui`** (design tokens / `DESIGN.md` when present; axe via `@axe-core/playwright`; findings as issues or notes), **`record-run`** (`templates/run.yaml`; `gen-tables.sh`), **`file-bug`** (`gh issue list --label type:bug --search` first; `templates/bug-issue.md`; assigns the feature owner from frontmatter; no real customer data).
- [ ] **Step 4: Run** `bash tests/run.sh` → the 22-skills test now PASSES; validate → no errors. **Commit** `feat: QA skills`.

### Task 16: Plugin CI, clean-room check, README

**Files:** Create `.github/workflows/ci.yml`, `tests/version-guard.sh`; add to `tests/repo.sh`; complete `README.md`

- [ ] **Step 1: Write tests:** `tests/repo.sh` assembles the forbidden-name pattern from split string pieces (so the test file itself never matches; the controller supplies the names in the dispatch) and asserts `git grep -i -E "$pattern"` over all tracked files finds nothing (and that the grep searched a non-empty file list); no CR characters in `*.sh`; `tests/version-guard.sh` with `BASE`: a diff touching `plugin/` must include `plugin/VERSION` and `CHANGELOG.md`.
- [ ] **Step 2: Run** → PASS (fix what fails).
- [ ] **Step 3: `ci.yml`:** `tests` on `ubuntu-latest` + `windows-latest` (`shell: bash`, `bash tests/run.sh`); `version-guard` (`fetch-depth: 0`); on PRs and pushes to `main`.
- [ ] **Step 4: README:** what it is; install at project scope (two commands, commit `.claude/settings.json`); `settings.local.json` to disable other plugins; adoption order (design §10); skills by role; how independence works (lanes, contracts, add-only, CODEOWNERS); hooks and their stated limits; what's enforced vs convention; the E2E-after-merge gap; contributing (bump VERSION + CHANGELOG, tests green).
- [ ] **Step 5: Commit** `chore: plugin CI, clean-room check, README`.

### Task 17: Install proof, dry runs, release

**Files:** Modify `CHANGELOG.md`

- [ ] **Step 1: Project-scope proof** in a throwaway repo: `claude plugin marketplace add D:/Projects/scrimpify-sdlc --scope project`; `claude plugin install scrimpify-sdlc@scrimpify-sdlc --scope project` → `.claude/settings.json` gains both entries; `claude -p "List the slash commands whose names start with scrimpify-sdlc"` there → the 22; in a second empty folder → none. **If the second folder lists them, stop and report to Bharath; no fallback.**
- [ ] **Step 2: Hook proof:** on `main`, `claude -p "Create notes.txt containing hi"` → refused; on `1-notes` → created. In an interactive session per permission mode the team uses (default, accept-edits, auto), ask Claude to run `gh issue create --title t --body t -R nobody/none`; confirm the guard-git prompt appears. Record per mode in CHANGELOG; if a mode skips it, add a chat confirmation rule to `STANDARD.md` and the outward skills.
- [ ] **Step 3: Synthetic two-feature dry run** in the throwaway repo (a tiny .NET or Node project with `docs/requirements/` of ~6 stories, no real GitHub writes: `gh` calls answered "no" at the prompt or pointed at a scratch repo Bharath names): `decompose` → 2 features + F00; `design-feature` on one; `build-feature` with two independent tasks running **in parallel**; confirm a subagent's out-of-lane edit is denied by guard-scope; `verify-feature full`; `write-test-cases` pass 1; `qa-browser` on a trivial page; every other skill run once. One CHANGELOG line per skill: worked / what was fixed.
- [ ] **Step 4:** Remove throwaway repos; `bash tests/run.sh` → all pass; set `## 0.1.0 — <date>`; commit `release: v0.1.0`.
- [ ] **Step 5: Publish — ask Bharath first:** create private `mathsyagiri-scrimpify/scrimpify-sdlc`, push `main` and `build/v0.1.0`, open the PR; after it merges, tag `v0.1.0` and push the tag. If his account can't create repos in that organisation, stop and say so.

---

## After this plan

Cowos adoption (design §10 steps 1–3) is a small separate plan run inside the Cowos repo after v0.1.0 is published; `decompose` on the requirements pack follows it.
