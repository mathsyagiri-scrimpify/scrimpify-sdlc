# Resume here: building scrimpify-sdlc v0.1.0

> Handoff written 2026-11-20 when the previous Claude session was stopped mid-build.
> This file is **not committed** (it is local working state). Delete it once the build is done.
> Paste this into the new session as the first message:
> "Read D:\Projects\scrimpify-sdlc\RESUME.md and continue the build from where it stopped."

## 1. What this is

`scrimpify-sdlc` is a Claude Code plugin (bash hooks + markdown skills + agents) that gives
Scrimpify's Cowos team (1 BA, 2 developers, 1 QA) one way of working with Claude, where **each
developer and tester works independently** (feature lanes, contracts, add-only shared files,
generated CODEOWNERS), a developer can run several task subagents in parallel on their own feature,
and everything stops at a merged PR. gstack is not needed.

- **Approved spec:** `docs/design.md` (v2, approved 2026-11-20). Binding.
- **Approved plan:** `docs/superpowers/plans/2026-11-20-scrimpify-sdlc-v0.1.md` (17 tasks).
- **Repo:** `D:\Projects\scrimpify-sdlc`, local only, no remote. Work branch `build/v0.1.0` (on top of an empty `main`).
- **Adopting repo (later):** `D:\Projects\Cowos` (`mathsyagiri-scrimpify/Cowos`).

## 2. Decisions Bharath made (don't re-ask)

- Write everything **fresh**. Never copy or open another organisation's plugin files (nothing under
  `C:\Users\*\.claude\plugins\` or `E:\`). The repo must not contain other organisations' names.
- Tracker: GitHub Issues in the Cowos repo. One monorepo.
- Parallel: a developer runs several task subagents on their own feature (`build-feature`).
- No gstack dependency; 22 skills cover everything. Pack stops at the merged PR; Cowos CI/CD deploys.
- PR review: **only cross-lane PRs** need another person (via generated CODEOWNERS); own-lane PRs
  merge on the AI review on record + green checks.
- Build method: **subagent-driven** (superpowers:subagent-driven-development): fresh implementer per
  task, a task reviewer after each, fix rounds, a final whole-branch review.
- Repo-local git identity is `bharath-gadipally <bharath-gadipally@users.noreply.github.com>` (the
  global identity is another employer's email; keep it out of this repo). Commit trailers:
  `Co-Authored-By: Claude <model> <noreply@anthropic.com>` and `Scrimpify-SDLC: v0.1.0`.
- Publishing to GitHub (Task 17 step 5) asks Bharath first. Nothing has been pushed.

## 3. Where the build stands

| Task | State |
|---|---|
| 1 Skeleton, manifests, test harness | ✅ complete, reviewed |
| 2 Hook library, STANDARD.md, session start | ✅ complete, reviewed (2 fix rounds) |
| 3 guard-branch | ✅ complete, reviewed |
| **4 guard-git** | ⏸ **in fix round 3 of 5, interrupted** (see §4) |
| 5–17 | not started (Task 5 brief already extracted) |

Commits on `build/v0.1.0` (newest first): `686cdac` (Task 4 fix round 2), `62ac924` (round 1),
`8b4c6bc` (Task 4), `1f4ce58` (Task 3), `b91a9ef`, `b4d1318`, `22b95a4` (Task 2), `213786c`,
`e07ed28`, `f9e739b` (Task 1), `2bf44e9` (initial, on `main`).

**Uncommitted:** the round-3 implementer was stopped mid-edit. Its unfinished, **unverified** changes
are in the working tree (`plugin/hooks/guard-git.sh`, `plugin/hooks/lib.sh`, `tests/hooks-git.sh`)
and saved as a patch at `.superpowers/sdd/2026-11-20-scrimpify-sdlc-v0.1/task-4-round3-wip.patch`.
Its last note was that a `sed` edit to an awk line didn't apply. Either finish from that state
(run `bash tests/run.sh` first) or discard it with `git checkout -- plugin tests` and redo round 3.

## 4. Task 4 fix round 3: the open findings

Fix base `686cdac`. Three open items (from the opus re-review; reproduction scripts in
`.superpowers/sdd/2026-11-20-scrimpify-sdlc-v0.1/probes/` — write probe harnesses with the Write tool,
because a Bash-tool heredoc halves `\\`):

1. **PowerShell backslash in `sdlc_words`** (lib.sh ~420-422): the double-quote pattern treats `\"` as
   an escape on raw `--ps` segments. `git -c "core.x=a\" push origin main` (PowerShell, branch 41-x)
   → allow/allow; `git push -o "ci\" origin main` → ask/deny (expected deny/deny). Fix: `--ps` mode
   for `sdlc_words` (backslash ordinary, backtick escapes in double quotes), passed from the hook.
2. **GraphQL mutation through `$(…)` now allowed (regression from round 2)**, lib.sh ~207
   (`ct = ct "$()"`): the raw segment that `handle_gh` reads lost the substitution text.
   `gh api graphql -f query="$(cat <<'EOF'`↵`mutation {…}`↵`EOF`↵`)"` and
   `gh api graphql -f query="$(echo 'mutation{x}')"` → allow/allow (must be ask/deny). Fix: keep the
   substitution text. **Ruling:** a GraphQL query whose visible text doesn't start with `query` or
   `{` (including variable/unreadable substitution) is treated as a write.
3. **Exponential parse on unclosed `"$(`** (lib.sh ~204-213): `findclose` returns len+1, the remainder
   is processed then rescanned → 2^n. `git push origin main; echo "$(`×n: n=21 takes 35 s; ~n=23
   passes the hook timeout with no decision (fails open). Fix: linear scan. **Ruling (fail closed):**
   a work budget (e.g. > 8× input length processed, or input > 32 KB) → ask (main) / deny (subagent)
   with reason "command too complex for guard-git to check"; test that n=40 decides within seconds.

Then: a scoped re-review (opus) of `686cdac..HEAD` against those three, then Task 4 is complete.
Round 4–5 rules if still open: a fresh implementer on a more capable model (fix-loop rules).

## 5. How to continue

1. Make sure the new Claude account has the **superpowers** plugin (for
   `superpowers:subagent-driven-development`). If not, follow the same loop by hand: implementer
   subagent per task → task reviewer → fix rounds (max 5) → final whole-branch review.
2. Read, in order: this file; `.superpowers/sdd/2026-11-20-scrimpify-sdlc-v0.1/progress.md` (the
   ledger: every ruling, deferred minor and completion); `constraints.md` in the same folder (binding
   constraints + pinned formats + controller rulings handed to every implementer); `docs/design.md`;
   the plan.
3. Reusable prompts in that folder: `reviewer-instructions.md` (task reviewer) and
   `rereview-instructions.md` (scoped re-review). Task briefs are extracted per task
   (`task-N-brief.md`); each implementer writes `task-N-report.md`.
4. Finish Task 4 round 3 (§4), then Tasks 5–17 in order. Notable rulings already in the ledger:
   the "22 skills present" test goes in **Task 15** (keeps the suite green); Task 16's clean-room test
   gets the forbidden names as split string pieces from the controller (so the test file itself
   doesn't match); Task 17's interactive permission-mode check goes to Bharath as a manual checklist.
5. The full test suite (`bash tests/run.sh`) takes ~5–7 minutes on this Windows machine. Run it in
   the background.
6. At the end: final whole-branch review on the most capable model, which must also triage the
   deferred minors in the ledger. Then Task 17's publish step: **ask Bharath first.**

## 6. After the plugin

Adopt it in Cowos (design §10): enable at project scope, update Cowos `CLAUDE.md` (remove gstack
routing, add Project checks), add the five Cowos checklists, run `decompose` on the requirements
pack (F00 Foundation first, `owns:` empty), settle the folder layout in F00's first task, then
`decompose --owns`. Flag to the product owner: re-plan for 2 developers; update `14-build-plan.md`'s
"second developer reviews every PR" rule; staffing moves to whole features.
