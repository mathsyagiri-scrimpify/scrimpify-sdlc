#!/usr/bin/env bash
# PreToolUse hook: deny file edits while the target repo is on a protected branch.
# Allow = exit 0 with no output. Unparseable or empty input also allows.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

sdlc_read_payload || exit 0

file="$(sdlc_json_str file_path)"
[ -n "$file" ] || file="$(sdlc_json_str notebook_path)"
[ -n "$file" ] || exit 0

repo="$(sdlc_repo_of "$file")"
[ -n "$repo" ] || exit 0

branch="$(sdlc_branch "$repo")"
[ -n "$branch" ] || exit 0
git -C "$repo" rev-parse --verify -q HEAD >/dev/null 2>&1 || exit 0   # unborn branch: nothing to protect yet

sdlc_protected "$repo" | grep -qxF -- "$branch" || exit 0

existing="$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null \
  | grep -E '^([0-9]+-.+|docs/.+|contract/.+)$' | sort | head -n 20)"

reason="Edits are blocked: this repo is on protected branch '$branch'. Create or switch to a work branch first. Branch forms: <issue>-<slug> (for example 41-product-pricing), docs/<slug>, contract/<slug>. Use the issue's real number and never invent an issue number; if there is no issue yet, file one first."
if [ -n "$existing" ]; then
  reason="$reason Existing local branches you may want: $(printf '%s' "$existing" | tr '\n' ' ' | sed 's/ $//')."
fi

sdlc_decide deny "$reason"
exit 0
