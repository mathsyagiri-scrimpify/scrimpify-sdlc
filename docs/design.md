# scrimpify-sdlc · Design (v2)

> Status: draft for approval · 2026-11-20 · Owner: Bharath
> Replaces the v1 draft of 2026-11-16. Written fresh for Scrimpify; it reuses no files or text
> from any other organisation's tooling. Workflow shape: shape → feature design → issue → plan →
> test-first build → fresh review → PR, with a subagent orchestrator for parallel tasks.

## 1. What this is and why

`scrimpify-sdlc` is a **Claude Code plugin** that gives a Scrimpify team one way of working with
Claude, from a product requirement to a merged pull request. Its first user is **Cowos**
(`mathsyagiri-scrimpify/Cowos`, one monorepo); any other Scrimpify repo on GitHub can adopt it
the same way. **gstack is not needed**: everything the team does in Cowos goes through this plugin.
gstack may stay installed as an optional extra.

**The main requirement (Bharath's words): each developer and tester works independently, without
depending on another developer or tester.** Everything in §3 serves that.

**The team:** 1 BA, 2 developers (the design must hold for more), 1 QA, all in Claude Code.

**Scope ends at the merged PR.** Deploys, Terraform applies, database scripts and rollouts belong
to Cowos's own CI/CD pipeline (staging on merge, production after a manual approval). The plugin
only makes Claude ask before running a deploy or infra command from a laptop.

**The guiding rule:** a rule that matters is enforced by a hook or a CI check. Anything left to a
skill's instructions is a convention, and the README says which is which.

## 2. Goals, non-goals, anti-goals

**Goals**
1. **Independence** (§3): two or more developers each build their own feature at the same time, and the QA tests a feature, without waiting on or breaking each other's work.
2. **Parallel inside a feature:** one developer runs several tasks of their feature at once, each built by a subagent in its own git worktree, under one build plan they approve once (§6.3).
3. Every change is traceable: requirement → feature → task issue → plan → commits → PR → merge, with the review on record.
4. Tests first, from the acceptance criteria, proven to fail without the code; a fresh reviewer that never saw the conversation checks every plan, design and change.
5. Nothing leaves the machine (push, PR, issue write) without a person saying yes; subagents can never push.
6. Requirements can be re-generated **one feature at a time** without touching other features.
7. Works on Windows (Git Bash) and macOS/Linux.

**Non-goals**
- Deploying, releasing, canary checks, production data work.
- Trackers other than GitHub Issues; issues spread across several repos.
- Claude Code web (cloud) sessions in v1 (CLI and desktop app, including its automatic worktrees, are in).
- Usage telemetry. Model-behaviour eval runs (v1 tests the hooks and dry-runs each skill).

**Anti-goals (it fails even if it "works" when…)**
- A developer has to wait for, coordinate with, or fix the work of another developer to finish their own feature, beyond the agreed foundation and contracts.
- Merging one feature breaks another feature's build or tests.
- It reports success without evidence: a test that never failed, an error shown as "nothing found", a skipped step reported as done.
- It changes behaviour in repos that did not adopt it (Bharath's machine also carries other employers' work).
- Secrets, real customer data or card data end up in git, prompts, issues or logs.

## 3. How independence works

Independence is designed in at planning time and then protected by hooks and CI. Seven mechanisms:

1. **Features are vertical slices with one owner.** `decompose` cuts the requirements into
   **features**: each one is something a user can do end to end (database → API → screen → test),
   that QA can test on its own, and that maps onto Cowos's modules (`Inventory`, `Booking`,
   `Payments`, `Sites`…). One developer owns a feature from design to merge.
2. **Every path is in one of three classes** (*my calls in this section, from the builder check*):
   - **Owned:** a feature's `requirements.md` frontmatter lists `owns:` globs. No two **active**
     features own the same path. Only the owner's PRs change them.
   - **Shared, add-only:** registration points every feature must touch, laid out by F00 so a
     feature only **adds** its own file or lines: module self-registration (each module/feature
     registers itself via its own `*Registration.cs`, discovered by convention), app routes and
     navigation (one route file per feature, collected by glob import), feature flags (one flag file
     per feature in a shared `Flags/` folder), architecture-test rules (one file per module),
     database migrations (one EF Core `DbContext`, schema and migrations folder **per module**, so
     two features never edit the same model snapshot). Any feature may add here; a CI check fails a
     diff that modifies or deletes existing lines in these paths.
   - **Shared, guarded:** everything else nobody owns (solution and root package files, shared UI
     packages, CI config, `docs/contracts/`, module `Contracts` projects). Changed only through
     `change-contract`.
   - **Generated, never committed:** the API client (`web/packages/api-client`) is generated from
     the OpenAPI spec at build time; `roadmap.md` and the master `test-plan.md` tables are
     **generated** by a script from each feature folder's frontmatter and files, so nobody
     hand-edits a shared table.
   - **Ownership lasts while a feature is active.** When a feature is complete (all tasks merged),
     its `owns:` is released; the next feature that extends that module claims the paths it needs
     in its own `requirements.md` (reviewed in its design PR). F00 lays out each module with
     per-feature subfolders (`src/Modules/Inventory/Features/SeatMaps/…`,
     `web/apps/admin/src/features/seat-maps/…`) so claims can be that fine. A feature that spans
     modules (e.g. "first paid booking": Booking + Payments) owns its subfolders in each.
   - Ownership is enforced through a **generated `CODEOWNERS`** (from active features' `owns:`)
     plus GitHub's "require review from code owners": an edit in your own lane needs nobody else;
     an edit in another active feature's lane needs that owner's approval on the PR.
   - This moves Cowos from layer-based staffing (14 §2: backend / admin / customer / platform) to
     **vertical** feature ownership, which independence requires.
3. **Contracts are written, and turned into code, before parallel work starts.** Everything that
   crosses a feature boundary is a **contract**: HTTP endpoints (OpenAPI fragments), events
   (schema), module public interfaces, and **table ownership** (nobody writes another module's
   tables). Each contract is a doc in `docs/contracts/` **and code**: the C# interface and DTOs in
   the provider module's `Contracts` project, plus an **in-memory fake** in `tests/Fakes/<Module>/`.
   The provider's owner writes all three in one `contract/` PR, merged first; it includes a
   **provider contract test** that runs the same test suite against the fake and (once it exists)
   the real implementation, so the fake can't drift. Consumers code against the interface and test
   with the fake; at runtime the real implementation is wired by the provider's module registration,
   so **nobody swaps anything**: when the provider merges, the real one is used. A consumer feature
   can merge **behind its flag** while its provider is unbuilt; its flag can only be switched on
   (and the feature called done for QA) once every provider it depends on has merged. The roadmap
   shows that state.
4. **A foundation feature comes first.** Some things everything depends on (Cowos: tenancy, auth,
   RLS, the solution skeleton, CI). `decompose` marks them as feature **F00 · Foundation**, built
   first. After it merges, features run in parallel. The roadmap shows the dependency graph: which
   features can start when.
5. **Changing shared things is its own small step.** Editing a contract or a shared path goes
   through `change-contract`: a small PR of its own that lists every feature affected and asks
   their owners to review. It merges before the feature work that needs it. Features never change a
   contract silently inside their own PR.
6. **Hooks keep work in its lane** (§7): `guard-scope` lets edits in owned and add-only paths
   through; an edit in another active feature's lane or a guarded shared path → **ask** in the main
   session (approving it means the PR will need that owner's CODEOWNERS approval, and the skill says
   so), **deny** for a subagent. Each developer works in their own clone; each task in its own
   worktree; tests use their own throwaway database (Testcontainers) and their own test tenant.
7. **Merging never breaks a neighbour.** Each feature merges to `main` in small PRs on its own
   schedule. Unfinished user-facing work stays behind its **feature flag** (off by default).
   - **On every PR:** all modules' unit and integration tests (Testcontainers PostgreSQL, real RLS)
     and every provider contract test. These catch nearly every cross-feature break before merge.
   - **After merge, on staging:** the full Playwright + axe end-to-end suite (needs the whole stack
     and Razorpay test mode, per 08 §15). This is a stated gap: an E2E-only break is found after
     merge, not before. A red post-merge E2E run files a bug against the **feature whose merge
     turned it red** (from the commit), not the feature whose test failed.
   - **The breaker fixes it.** A PR that turns another feature's tests red doesn't merge: either it
     broke a contract (fix your own code) or the contract must change (`change-contract`). If `main`
     itself goes red, **anyone may revert the merge that caused it** (reverting is always allowed
     out of lane) and the author re-lands it. A flaky test may be quarantined by anyone with a
     `flaky` issue assigned to its owner; quarantined tests are listed in the CI summary.

**QA independence**
- QA writes a feature's test cases **from its requirements and contracts at design time**, before
  code exists (first pass), so QA never waits for a build to start working. After the build, a
  second pass refines them against what was built.
- Automated end-to-end tests live per feature (`tests/e2e/<feature>/`), each creating its own test
  tenant and data, so one feature's tests never depend on another's data.
- QA tests a feature with `qa-browser` **on `main` with the feature's flag turned on for a QA test
  tenant** (locally from their own clone, or on staging). For an early look before the tasks have
  all merged, QA can run the tip of the feature's task stack in their own worktree. Bugs are filed
  against the feature and its owner.
- **A design never waits on QA.** The feature design PR merges on the owner's say (plus the review
  rule in §9); QA's first-pass test cases are QA's own docs PR, written in parallel.
- Cases that span two features (e.g. booking a seat on a seat map) are marked **cross-feature** and
  run once both features have merged; they are the only QA work that waits.

**BA independence**
- `change-request` works on one feature at a time: it re-generates that feature's requirements and
  updates its issues. If the change would alter a contract, it stops and routes through
  `change-contract`, so other features are only touched with their owners' agreement.

## 4. Install and activation

- **Repo:** private, `mathsyagiri-scrimpify/scrimpify-sdlc` (*my call*). It is its own plugin
  marketplace with one plugin, `scrimpify-sdlc`.
- **Nothing to deploy.** Releasing = merging to `main` and tagging `vX.Y.Z`. Teammates need GitHub
  access to the repo, `gh` logged in, Git Bash on Windows.
- **Per project, never per user.** A repo adopts it by committing in `.claude/settings.json` the
  marketplace (`extraKnownMarketplaces`) and the plugin (`enabledPlugins`), using
  `claude plugin marketplace add … --scope project` and `claude plugin install … --scope project`.
  It is inert in every other folder. *If project-scoped enabling turns out not to keep it inert
  elsewhere, stop and come back to Bharath; no user-scope fallback.*
- **Other employers' plugins** installed at user scope are disabled for the adopting repo in its
  uncommitted `.claude/settings.local.json` (README step; no such plugin is named in committed files).
- **Updates:** `claude plugin update scrimpify-sdlc@scrimpify-sdlc`. A session-start check prints one
  line when a newer tag exists, or that the check failed; never nothing on failure.

## 5. Artifacts in the adopting repo (Cowos)

```
Cowos/
├── CLAUDE.md                       project context, Project checks, skill routing
├── .claude/settings.json           enables the plugin
├── src/ · web/ · renderer/ · infra/ · tests/      code (layout settled in F00)
└── docs/
    ├── requirements/               INPUT: BA's requirements pack (exists)
    ├── designs/                    INPUT: approved product/tech design (exists)
    ├── product/
    │   ├── roadmap.md              features, owners, dependency graph, status
    │   └── test-plan.md            master test plan: objectives, coverage table, run summary
    ├── contracts/                  one file per contract (endpoints, events, interfaces, tables)
    ├── features/
    │   └── f03-inventory/
    │       ├── requirements.md     what it delivers; frontmatter: id, owner, status, owns:, depends_on:, contracts:
    │       ├── design.md           how it is built, its contracts used/provided
    │       ├── decisions.md        each decision + rejected alternatives
    │       ├── tasks.md            one line per task: `- [ ] T001 [ready:agent] Title`
    │       ├── bodies/T001.md      one per task: story, criteria with ids, depends-on, files
    │       ├── test-plan.md        QA's cases for this feature (TC-F03-NN)
    │       └── build.md            the orchestrator's living build plan (when used)
    ├── work/<year>/<issue>-<slug>/plan.md     one per task issue
    └── test-runs/<yyyy-mm-dd>-<slug>.yaml     one per manual QA run
```

**Conventions:**
- Feature ids `F00`…; folders `f03-<slug>`. Task ids `T001` within a feature. Acceptance criteria
  ids `#<issue>/AC<k>` once filed; tests carry the criterion id in their name or a tag so coverage
  can be counted.
- One task = one GitHub issue = one PR. Labels: `type:feature|task|bug|contract`, `feature:f03`,
  `area:api|admin|booking|website|ops|marketing|renderer|infra`, readiness
  `ready:agent|ready:human|needs-detail`. Milestones = sprints.
- Branches: task `<issue>-<slug>`; docs-only `docs/<slug>` (needs no issue); contract changes
  `contract/<slug>` (needs a `type:contract` issue).
- PR title `[#41] …`; body has `Closes #41`.
- Commit trailers: `Co-Authored-By: Claude <model> <noreply@anthropic.com>` and `Scrimpify-SDLC: v<version>`.

**Readiness** (per task, set at design time, re-checked at pick-up):
`ready:agent` — every criterion provable by a command whose output differs when the work isn't
done; `ready:human` — fully specified but a person must judge at least one criterion;
`needs-detail` — some criterion can't be judged by anyone as written; refused by `file-issues`.
Rewriting a criterion just to make a task `ready:agent` is not allowed.

## 6. The workflow and skills

All skills are `/scrimpify-sdlc:<name>`. 22 skills, two agents.

### 6.1 Planning (BA leads; developers own feature design)

| Skill | Who | What it does | Human stop |
|---|---|---|---|
| `shape` | Anyone | Raw idea → problem, desired outcome, how success is judged, in/out of scope, open questions. Replaces gstack's product-thinking session. | None |
| `decompose` | BA + a developer | The requirements pack (`docs/requirements/`, `docs/designs/`) → `roadmap.md` (features, owners, dependency graph, F00 first), the master `test-plan.md` objectives, a `requirements.md` per feature with `owns:` and `depends_on:`, and the first `docs/contracts/` between features. Refuses overlapping `owns:`. No tasks. Draft on a `docs/` branch, reviewed by a fresh reviewer, approved by merging its PR. **Re-runnable for one feature** (`decompose --feature f03`) without touching others; a change that would alter another feature's contract stops and points to `change-contract`. | Merging the PR |
| `design-feature` | Feature owner | `design.md`, `decisions.md`, the feature's own contracts, `tasks.md` (readiness per task, dependencies between tasks so the orchestrator knows what can run in parallel), `bodies/`, and the first pass of `test-plan.md` requested from QA (§6.4). Fresh reviewer (`review-design`) before hand-over. Draft PR, approved by merging. | Merging the PR |
| `review-design` | Anyone | Fresh reviewer on a feature design, the roadmap or a contract, with three lenses: scope and product fit, architecture and contracts, user experience. Loops fresh full rounds up to 3. Replaces gstack's plan reviews. | Which findings to fix |
| `file-issues` | Feature owner | Files the merged feature's tasks as issues in one preview and one confirmation; adopts existing issues; refuses `needs-detail`; records each task's issue number in `tasks.md` (`T001 … #41`) on a `docs/` branch. | One confirmation |
| `create-issue` | Anyone | A one-off story, task or contract issue outside a feature plan, in the house format. | Confirms the issue |
| `change-request` | BA | The product owner changed something: finds affected requirements, tasks, issues, test cases **within one feature**; re-generates that feature's requirements; updates issue bodies with a comment saying what changed; flags merged work that no longer fits; never reverts it. Stops and hands over to `change-contract` if a contract would change. | Confirms the issue writes |
| `change-contract` | Developer | Proposes a contract change: the diff to `docs/contracts/`, every feature that uses it (from frontmatter `contracts:`), what each must change; opens a `contract/<slug>` PR requesting review from each affected owner. | Push + PR |

### 6.2 Building one task by hand

| Skill | What it does | Human stop |
|---|---|---|
| `pick-up <issue>` | Fetches the issue and comments (a failed fetch is a stop, never "no issue"); re-checks readiness; reads the feature's design, contracts, the cited requirements and the code on freshly fetched `main`; writes `plan.md` (§6.5); fresh plan reviewer, up to 2 rounds; presents the plan in full. Branch: creates `<issue>-<slug>` from fresh `origin/main` (or from its parent task's branch when stacked); renames an automatic `claude/<name>` session branch with no commits of its own; resumes an existing one. | **Plan approval** (branch name proposed in the same message) |
| `build` | One acceptance criterion at a time: test from the criterion → run it, show it failing → smallest code → run the area's suite. Commits on the work branch. Stays inside the feature's `owns:` paths; anything outside is a stop (contract change or a note for another owner). Struck-through plan steps keep their reason. | Only if the plan must change |
| `verify` | The repo's checks for the touched areas ("no checks configured for <area>" when none, never "passed"); then three fresh reviews in parallel: **design** (diff vs issue, plan, feature design, contracts, repo checklists), **bite** (each new/changed test is broken on a scratch copy and must go red), and Claude Code's built-in `/code-review`. Fixes with the developer's go; scoped follow-up review of non-trivial fixes; up to 3 rounds. Writes `## Review` into `plan.md`. | Which findings to fix, when not obvious |
| `open-pr` | Exit check (review recorded and `Result: PASS`, every criterion has a passing test or an accepted test gap, trailers, checks shown), PR body (Story / What changed / How it was tested / QA notes / `Closes #N`), lists push + PR + issue comment (+ a review request only to the code owners the diff triggers; none for an own-lane PR), then does them on one yes. Own-lane PRs: once required checks are green, offers to merge (`gh pr merge --squash`, its own yes). **Docs mode** for `docs/` branches (no plan or review needed; checks every id and link cited resolves). | **Push + PR** |
| `fix-review [pr]` | New PR comments and failing checks in one pass; fixes what it agrees with, drafts replies (reasons when it disagrees), scoped review of non-trivial fixes. | Push + replies, one yes |
| `update-issue` | Scope or a criterion changed mid-work: issue body updated to the current truth plus a comment why; `plan.md` updated; tells the BA if the feature's requirements need the same change. | Confirms the issue write |
| `investigate` | A bug or failing test: reproduce first, find the root cause with evidence (file:line, command output), propose the fix; the fix then goes through an issue and the normal flow. Replaces gstack's debugging skill. | None (the fix has its own gates) |

### 6.3 Building a whole feature in parallel (the orchestrator)

| Skill | What it does |
|---|---|
| `build-feature <feature>` | For a feature whose design is merged. Files missing issues (via `file-issues`). Writes `build.md`: the tasks, their dependency order, which run in parallel (default **max 3 at a time**), stacks for dependent tasks, and check-in milestones. **The developer approves `build.md` once.** Then it dispatches one `task-builder` subagent per ready task, each in its own git worktree, and keeps `build.md` current (state, open questions, waiting-on-you list). Re-running it resumes from `build.md`. |
| `verify-feature <feature> [small T00x \| full]` | Small mode after each task lands: does it fit its contracts with its neighbouring tasks? Full mode at milestones and the end: every criterion and contract of the feature, gaps no task owns, plus `/code-review` on the feature's combined diff. Up to 3 fresh rounds. |

**Rules of the orchestrated build:**
- **Decision rule:** a decision the feature design didn't settle is listed in the task's plan and stops **only that task** until the developer confirms it or says "AI decides". A plan that would change the design, a contract or the criteria, or fails its Size check, also stops for the developer. Other tasks continue. Silence is never consent.
- **Subagents** plan with `pick-up`'s rules (plan review included, no human plan approval), build with `build`, verify with `verify`, commit locally, and return a structured result. They never push, open PRs, comment on GitHub, use the git stash, remove worktrees, prune Docker, kill processes by name, install software, or run infra applies: hooks block all of these for subagents.
- **Push gate:** everything outward from a run (branches, PRs, issue comments, review replies) is listed together and goes out on one yes; the developer may approve part of it. Each PR's review round is its own gate. Independent tasks get PRs off `main`; dependent ones stack on their parent's branch.
- **Questions** come to the developer in chat, one topic at a time, with a recommendation; every open one is kept in `build.md` until answered.
- **PR feedback** goes back to the task's subagent (`fix-review` rules).

### 6.4 QA

| Skill | What it does | Human stop |
|---|---|---|
| `write-test-cases <feature>` | **Pass 1 (design time):** cases from the feature's requirements, criteria and contracts, before code. **Pass 2 (after build):** refine against what was built, link automated tests. Cases `TC-F03-NN`, each traced to a criterion, classed **Automated** (layer + file) or **Manual** (reason), priority, steps, expected result; a control case for every critical flow (e.g. tenant A's booking never visible to tenant B); cross-feature cases marked as such. Updates the master coverage table. Proposes automation issues for manual cases that could be automated. | Confirms any issues |
| `qa-browser <feature> [--branch]` | Runs the app (the feature's branch in QA's own worktree, or staging) and walks each case in a real browser with Playwright, saving screenshots under the run; writes a run record; drafts bugs for failures. Replaces gstack's browser QA. | Confirms bugs to file |
| `review-ui <feature>` | Checks the feature's screens against the design tokens / theme rules (`DESIGN.md` when present) and runs axe accessibility checks; files findings as issues or notes. Replaces gstack's visual review. | Confirms issues |
| `record-run` | After a manual run: one YAML record (tester, date, commit, environment, per-case result), rolls it into the master run summary, drafts a bug per failure. | Confirms bugs |
| `file-bug` | Repro steps, expected vs actual, environment + commit, the feature and criterion broken, severity; searches open bugs first and comments on a duplicate instead. Assigns the feature owner. No real customer data. | Confirms the issue |

### 6.5 `plan.md` (one per task issue)

Header (issue, feature, task id, branch, contracts touched) · **Checked** (facts with `path:line`
and how each was confirmed; assumptions labelled) · **Approach and steps** (ordered, what and why,
files table, runnable verification with expected results) · **Tests** (one row per criterion id →
test name, layer, file; or an accepted **test gap** with its reason) · **Checklists** (repo
checklists that apply) · **Decisions** (open/settled, by whom) · **Size** (one session, one
readable PR, inside the feature's `owns:`? else split) · **Risks** · **Review** (added by `verify`,
ends `Result: PASS|FAIL`).

## 7. Enforcement

### 7.1 Hooks (pure bash + git; no jq/python/node; tested on Windows Git Bash and Linux)

| Hook | When | Behaviour |
|---|---|---|
| `session-start` | start/resume/clear/compact | Injects the standard (`STANDARD.md`, ≤ 8 KB) with the version; update check on startup. |
| `guard-branch` | Write/Edit/MultiEdit/NotebookEdit | Blocks edits in a repo on `main`/`master`/its default branch; lists existing work branches; asks Claude to propose `<issue>-<slug>`, `docs/<slug>` or `contract/<slug>` and get it confirmed; never invent an issue number. Files outside a repo, detached HEAD and unborn branches pass. |
| `guard-scope` | Write/Edit/MultiEdit/NotebookEdit | Finds the current task's feature (the branch's `plan.md` header) and that feature's `owns:` globs. Allows the feature's owned paths, add-only paths, and the task's own `docs/work/` folder. An edit in another active feature's lane or a guarded shared path → **ask** in the main session (the reason names the owner whose approval the PR will need, or "shared path → use change-contract"), **deny** for a subagent. No plan found → no check. |
| `guard-git` | Bash/PowerShell | **Deny:** push to a protected branch, force push (except `--force-with-lease` on a work branch), commit on a protected branch, `--no-verify`. **Ask (main session):** any other push; `gh` PR/issue/label/milestone writes; `gh api` writes and GraphQL mutations. **Deny for subagents:** all of the "ask" set. Reads pass. Quoted text is blanked before matching; compound, chained and wrapped commands are checked segment by segment. |
| `guard-shared` | Bash/PowerShell, subagents only | Deny: `git stash`, `git worktree remove/prune`, `docker system/volume/image prune`, removing all containers, killing processes by name, package/software installs outside the repo, deleting the shared scratchpad. |
| `guard-rails` | Bash/PowerShell/Read/Grep/Glob/Edit/Write | **Deny reads** of credential stores and keys (`~/.ssh/id_*`, `~/.aws/credentials`, `~/.aws/sso/cache`, `~/.config/gh`, the Windows gh hosts file, `*.pem`, `*.key`, `*.pfx`, `.env*` except `.env.example`/`.env.sample`). **Deny edits** of shell startup files and global git/gh config. **Ask:** `terraform`/`terragrunt` apply/destroy, AWS commands that change resources, anything naming a production profile or host. |

Subagent = a hook payload carrying an agent id (the builder must confirm the field name on the
current Claude Code version). Hooks match command text, so a command assembled at run time is not
seen: a strong default, not a sandbox; the README says so. The builder confirms that hook "ask"
still prompts in the permission modes the team uses; if a mode skips it, the skills also confirm in chat.

### 7.2 Reviews

The `reviewer` agent is always fresh, never sees the conversation, gets a **brief** from
`reviews/` plus the material, and returns a first line `VERDICT: PASS` or `VERDICT: FAIL`, then
findings `- [blocking|note] <file>:<line> — <what> — <evidence>`.

| Brief | Used by | Rounds |
|---|---|---|
| `plan` | `pick-up`, task-builder | 2 |
| `design` | `verify` (code vs issue/plan/design/contracts/checklists) | with the code limit |
| `bite` | `verify` | with the code limit |
| `fix` | `verify`, `fix-review` (scoped follow-up) | code limit 3 in total |
| `feature-design` | `design-feature`, `review-design`, `decompose` (with the three lenses) | 3 fresh full rounds |
| `feature` | `verify-feature` | 3 fresh full rounds |

**Blocking:** wrong behaviour, a criterion or contract broken, an edit outside the feature's owned
paths, a test that doesn't bite, an error reported as success, secrets or real data, out-of-scope
change. In documents: a false statement, a contradiction, a dependency cycle, overlapping `owns:`,
a requirement no task covers. Style and wording are notes. Trivial fixes are listed as "not
re-reviewed". At a round limit, remaining findings go to the person with a recommendation each.

### 7.3 Repo checklists

Any `docs/sdlc/checklists/<name>.md` in the repo is a rule list that the plan, design and code
reviewers apply when a change touches its area. The plugin ships two generic examples (API
contract; React UI + accessibility). Cowos adds at adoption, from its NFRs: tenant isolation
(NFR-MT), payments/PCI (NFR-PCI), privacy/DPDP (NFR-PRIV, NFR-OBS-01), module boundaries
(08 §4), billing reproducibility (NFR-MTR-02).

### 7.4 CI (templates a repo wires; Cowos wires them in F00)

- GitHub Actions template for a .NET + React monorepo: path-filtered jobs per area, but **every
  feature's tests run on every PR that touches code** (so a break shows on the PR that caused it);
  docs-only PRs run only docs checks.
- Check scripts: **review-on-record** (skipped, saying so, for docs-only PRs), **owns-overlap**
  (no two active features' `owns:` overlap; `CODEOWNERS` matches what `owns:` generates),
  **add-only** (no modified or deleted lines in add-only paths), **lane** (a changed path in
  another feature's lane or a guarded shared path is reported; GitHub's code-owner review is what
  blocks it), **criteria-coverage** (every criterion id of the task's issue
  appears in a test name/tag or as an accepted test gap in `plan.md`), **todo-has-issue**,
  **tests-changed** (flag only).
- They bind only once marked required in branch protection.

### 7.5 The plugin's own CI

Hook tests on `ubuntu-latest` and `windows-latest`; check-script tests; a version guard (any
change under `plugin/` bumps `VERSION` and `CHANGELOG.md`); a clean-room check (no other
organisation's names anywhere in the repo).

## 8. The standard (always loaded, ≤ 8 KB)

In Scrimpify's own words: understand before acting · issue first (docs-only exempt) · plan,
approve, build (by hand per issue; orchestrated via the decision rule) · tests first, behaviour
not implementation, criterion ids on tests · review before PR · nothing outward without a yes ·
never on main · **stay in your feature's lane; shared things change only through
change-contract** · stay in scope · data and secrets · honest reporting · ask well (one topic at
a time, material first, recommendation, open questions tracked) · keep artifacts current
(history only in decisions.md, plan Review, struck-through steps, issue/PR comments) · repo rules
win · resume from branch + `plan.md` + `build.md`, never from memory · the pack ends at merge.

## 9. Gates in one place

| Stop | Who | How |
|---|---|---|
| Decomposition / roadmap / contracts | BA + developers | Merge the docs PR |
| Feature design | Owner, after the fresh `review-design` passes (other developer and QA may comment; their approval isn't required unless the design claims their lane or changes a contract) | Merge the docs PR |
| Contract change | Every affected feature owner | Approve the `contract/` PR |
| Issue question (by hand) | Developer | Chat |
| Task plan (by hand) | Developer | Chat, plan in full first |
| Build plan (orchestrated) | Feature owner | Chat, `build.md` in full first |
| Open decisions (orchestrated) | Feature owner | Chat; only that task waits |
| Push / PR / issue writes | Whoever runs the skill | One listed yes (push gate); hook prompt behind it |
| Code PR, own lane only (decided) | The feature owner | Owner merges once the AI review is on record (`Result: PASS`) and every required check is green; no second human needed |
| Code PR touching another lane, a contract or a guarded shared path (decided) | That lane's owner / the contract's affected owners | GitHub "require review from code owners" with the generated `CODEOWNERS` |

## 10. Adopting it in Cowos (after v0.1.0 is published)

1. Enable the plugin at project scope; Bharath's `settings.local.json` disables other plugins there.
2. `CLAUDE.md`: remove the gstack routing; add "Project checks" (areas marked *not configured
   yet* until F00 creates them) and point to the checklists.
3. Add the five Cowos checklists.
4. Run `decompose` on the requirements pack → roadmap with F00 Foundation first, the features,
   their owners, dependencies and first contracts, **with `owns:` left empty**. Review and merge.
5. F00's first task settles the folder layout (`08-architecture.md` §15 vs `14-build-plan.md`
   disagree) including the per-module, per-feature subfolders and the add-only registration points.
6. `decompose --owns` then fills every feature's `owns:` against the real layout in **one** docs
   PR, approved by the BA and the developers, before any feature after F00 starts. Then features
   run in parallel.

**Flagged for the product owner, outside the plugin:**
- The build plan is staffed for 4 developers; with 2, the dates need re-planning (`decompose`'s roadmap will show the real order).
- `14-build-plan.md` §1/§8 say a second developer reviews every PR. The team has decided: only PRs that cross into another feature's lane, a contract or a guarded shared path need another person; own-lane PRs merge on the AI review plus green checks. That text should be updated.
- Staffing moves from layers (backend / admin / customer / platform) to whole features.
- Branch protection on `main` (owner sets it in GitHub): required checks, "require review from code owners", no required approval count otherwise.

## 11. Left to the builder

Wording of every skill, brief, template and the standard; hook pattern details and their tests;
template fields beyond those named; label colours; CI template details; README structure.

## 12. Done when

- Installs from its GitHub repo into a repo at project scope and is inert in a folder that hasn't enabled it.
- Hook and check-script tests pass on Linux and Windows.
- All 22 skills exist, each run once in a throwaway repo (with a synthetic two-feature project), including one `build-feature` run with two tasks in parallel and one `guard-scope` refusal for a subagent; results noted in the CHANGELOG.
- The Cowos adoption PR (§10 steps 1–3) is open for review.
