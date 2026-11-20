#!/usr/bin/env bash
# Tests: hook library, STANDARD.md, session-start, check-update.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"
. "$HERE/fixtures.sh"
LIB="$ROOT/plugin/hooks/lib.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "STANDARD.md"
STD="$ROOT/plugin/STANDARD.md"
if [ -f "$STD" ]; then
  size="$(wc -c < "$STD" | tr -d ' ')"
  if [ "$size" -le 8192 ]; then pass "STANDARD.md is $size bytes (<= 8192)"; else fail "STANDARD.md is $size bytes"; fi
  body="$(cat "$STD")"
else
  fail "STANDARD.md exists"; body=""
fi
for h in "Understand before acting" "Issue first" "Plan, approve, build" "Tests first" \
  "Review before PR" "Nothing outward without a yes" "Never on main" "Stay in your lane" \
  "Stay in scope" "Data and secrets" "Honest reporting" "Ask well" "Keep artifacts current" \
  "Repo rules win" "Resume from files" "Ends at merge"; do
  expect_contains "$body" "## $h" "STANDARD.md heading: $h"
done

echo "lib.sh"
if [ -f "$LIB" ]; then . "$LIB"; else fail "lib.sh exists"; fi

expect_eq "$(sdlc_to_posix_path 'D:\Projects\x')" "/d/Projects/x" "posix path from backslashes"
expect_eq "$(sdlc_to_posix_path 'D:/Projects/x')" "/d/Projects/x" "posix path from forward slashes"
expect_eq "$(sdlc_to_posix_path '/d/Projects/x')" "/d/Projects/x" "posix path unchanged"

SDLC_PAYLOAD='{"tool_input":{"command":"echo \"hi\""}}'
expect_eq "$(sdlc_json_str command)" 'echo "hi"' "json_str unescapes quotes"
SDLC_PAYLOAD='{"tool_input":{"file_path":"D:\\Projects\\a.cs"}}'
expect_eq "$(sdlc_json_str file_path)" 'D:\Projects\a.cs' "json_str unescapes backslashes"
SDLC_PAYLOAD='{"tool_input":{}}'
expect_empty "$(sdlc_json_str command)" "json_str missing key is empty"

SDLC_PAYLOAD='{"agent_id":"abc123","tool_input":{}}'
if sdlc_is_subagent; then pass "subagent with agent_id"; else fail "subagent with agent_id"; fi
SDLC_PAYLOAD='{"agent_id":"","tool_input":{}}'
if sdlc_is_subagent; then fail "empty agent_id is not a subagent"; else pass "empty agent_id is not a subagent"; fi
SDLC_PAYLOAD='{"tool_input":{}}'
if sdlc_is_subagent; then fail "no agent_id is main session"; else pass "no agent_id is main session"; fi

out="$(printf '' | { sdlc_read_payload; echo "rc=$? out=[$SDLC_PAYLOAD]"; })"
expect_eq "$out" "rc=1 out=[]" "empty stdin: read_payload returns 1"
printf '' | bash -c ". '$LIB'; sdlc_read_payload || exit 0" > "$TMP/o" 2>&1; rc=$?
expect_eq "$rc" "0" "empty stdin exits 0"
expect_empty "$(cat "$TMP/o")" "empty stdin prints nothing"
out="$(printf '{"a":\n"b"}\n' | { sdlc_read_payload; echo "$SDLC_PAYLOAD"; })"
expect_eq "$out" '{"a":"b"}' "read_payload strips newlines"

expect_eq "$(printf 'a "b" \\c\nline2\r\n' | sdlc_json_escape)" 'a \"b\" \\c\nline2' "json_escape"

out="$(sdlc_decide deny 'no "push" here')"
expect_eq "$out" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no \"push\" here"}}' "decide output"

make_repo "$TMP/r" main
mkdir -p "$TMP/r/sub/dir"
expect_eq "$(sdlc_repo_of "$TMP/r/sub/dir/not-yet/file.txt")" "$(sdlc_to_posix_path "$(git -C "$TMP/r" rev-parse --show-toplevel)")" "repo_of nearest existing ancestor"
expect_empty "$(sdlc_repo_of "$TMP/nope-outside/file.txt")" "repo_of outside any repo is empty"
repo="$(sdlc_repo_of "$TMP/r/sub")"
expect_eq "$(sdlc_rel_path "$repo" "$repo/sub/dir/x.cs")" "sub/dir/x.cs" "rel_path"
expect_eq "$(sdlc_branch "$repo")" "main" "branch"
git -C "$TMP/r" checkout -q --detach
expect_empty "$(sdlc_branch "$repo")" "branch empty when detached"
git -C "$TMP/r" checkout -q main
prot="$(sdlc_protected "$repo")"
expect_contains "$prot" "main" "protected has main"
expect_contains "$prot" "master" "protected has master"
git -C "$TMP/r" update-ref refs/remotes/origin/trunk HEAD
git -C "$TMP/r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
expect_contains "$(sdlc_protected "$repo")" "trunk" "protected has origin/HEAD default"

echo "session-start"
out="$(bash "$ROOT/plugin/hooks/session-start.sh" </dev/null)"
ver="$(tr -d '\r\n' < "$ROOT/plugin/VERSION")"
expect_contains "$out" "scrimpify-sdlc v$ver is active in this repo." "session-start mentions version"
expect_contains "$out" "Understand before acting" "session-start carries the standard"
printf '%s' "$out" > "$TMP/ss.json"
ok="$(pyjson 'import json,sys
d=json.load(open(sys.argv[1]))["hookSpecificOutput"]
print("ok" if d["hookEventName"]=="SessionStart" and "Plugin files:" in d["additionalContext"] else "bad")' "$TMP/ss.json")"
expect_eq "$ok" "ok" "session-start output parses as JSON with the right shape"

echo "check-update"
make_repo "$TMP/src" main
git -C "$TMP/src" tag v0.1.0
git clone -q --bare "$TMP/src" "$TMP/remote.git"
cu() { SCRIMPIFY_SDLC_REMOTE="$1" bash "$ROOT/plugin/hooks/check-update.sh" </dev/null; }
expect_empty "$(cu "$TMP/remote.git")" "current version prints nothing"
git -C "$TMP/src" tag v0.2.0
git -C "$TMP/src" push -q "$TMP/remote.git" v0.2.0 2>/dev/null
out="$(cu "$TMP/remote.git")"
expect_contains "$out" "scrimpify-sdlc v0.2.0 is available (installed v$ver)" "newer tag announced"
expect_contains "$out" "claude plugin update scrimpify-sdlc@scrimpify-sdlc" "update command given"
out="$(cu "$TMP/no-such-remote.git")"
expect_contains "$out" "scrimpify-sdlc update check failed:" "missing remote reports failure"

finish
