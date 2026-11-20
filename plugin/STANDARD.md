# scrimpify-sdlc standard

Always in force in this repo. Skills add detail; a hook block means stop and ask, not work around.

## Understand before acting
Read the issue, the feature design, the contracts and the code on a fresh `main` before changing anything. A failed fetch is a stop, never "nothing found".

## Issue first
Every change traces to an issue. Docs-only changes on a `docs/` branch are exempt.

## Plan, approve, build
By hand: write `plan.md`, get it reviewed, get the developer's approval, then build. Orchestrated: a decision the design did not settle stops only that task until the developer answers or says "AI decides". Silence is never consent.

## Tests first
One acceptance criterion at a time: write the test from the criterion, run it, see it fail, then write the smallest code. Test behaviour, not implementation. Put the criterion id (`#41/AC1`) in the test name or a comment. A criterion with no test needs a stated, accepted test gap.

## Review before PR
Run `verify` and record `Result: PASS` in `plan.md` first. Reviewers are fresh, never the author's own context. No PR without it.

## Nothing outward without a yes
Pushes, PRs, issue writes, comments and review replies are listed and go out on the developer's yes. Subagents never do them. Unless asked, no force-push, stash, worktree removal, installs or infra applies.

## Never on main
No commits or pushes on `main`, `master` or the repo's default branch. Branches: `<issue>-<slug>`, `docs/<slug>`, `contract/<slug>`.

## Stay in your lane
- Edit only paths your feature owns (`owns:` in its `requirements.md`) and add-only paths by adding. Anything else changes through `change-contract`, or becomes a note for its owner.
- If a PR turns another feature's tests red, you fix it: your code broke a contract, or the contract must change.
- If `main` goes red, anyone may revert the merge that caused it; the author re-lands it.
- A flaky test is quarantined by anyone, with a `flaky` issue assigned to its owner.

## Stay in scope
Do what the issue asks. Spot something else: note it or file it, do not fold it in.

## Data and secrets
No real customer data in code, tests, issues or logs. No secrets in the repo, commands or messages. Use fakes and test tenants.

## Honest reporting
Say what ran and what it showed. "No checks configured" is not "passed". State what you did not verify. Never claim success without evidence.

## Ask well
One topic at a time, the material question first, with your recommendation. Keep every open question written in `build.md` or the plan until answered.

## Keep artifacts current
Issue, `plan.md`, `tasks.md` and `build.md` match reality. History lives only in `decisions.md`, the plan's Review, struck-through steps (with the reason) and issue or PR comments.

## Repo rules win
The repo's `CLAUDE.md`, checklists and CI beat this standard where they are stricter or differ. Say so when it happens.

## Resume from files
After a break, rebuild state from the branch, `plan.md` and `build.md`, never from memory.

## Ends at merge
The pack's work finishes at merge. Deploys, releases and ops belong to the team's own process.

## Commit trailers
End every commit message with:
`Co-Authored-By: Claude <model> <noreply@anthropic.com>`
`Scrimpify-SDLC: v<plugin version>`

## Skills by role
All are `/scrimpify-sdlc:<name>`.
- Anyone: `shape`, `review-design`, `create-issue`, `investigate`
- BA: `decompose`, `change-request`
- Feature owner: `design-feature`, `file-issues`, `build-feature`, `verify-feature`
- Developer: `pick-up`, `build`, `verify`, `open-pr`, `fix-review`, `update-issue`, `change-contract`
- QA: `write-test-cases`, `qa-browser`, `review-ui`, `record-run`, `file-bug`
