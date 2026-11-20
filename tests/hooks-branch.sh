#!/usr/bin/env bash
# Tests: guard-branch (blocks edits on protected branches).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"
. "$HERE/fixtures.sh"
HOOK="$ROOT/plugin/hooks/guard-branch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# run_hook <stdin-text>: sets OUT and RC.
run_hook() {
  OUT="$(printf '%s' "$1" | bash "$HOOK" 2>/dev/null)"; RC=$?
}
# write_payload <file_path-as-json-body>
write_payload() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1"; }

expect_deny() { # payload msg
  run_hook "$1"
  expect_eq "$RC" "0" "$2: exit 0"
  expect_contains "$OUT" '"permissionDecision":"deny"' "$2: denies"
}
expect_allow() { # payload msg
  run_hook "$1"
  expect_eq "$RC" "0" "$2: exit 0"
  expect_empty "$OUT" "$2: no output"
}

if [ ! -f "$HOOK" ]; then fail "guard-branch.sh exists"; finish; fi

echo "protected branches"
make_repo "$TMP/r-main" main
RM="$(cd "$TMP/r-main" && pwd)"
run_hook "$(write_payload "$RM/src/a.cs")"
expect_eq "$RC" "0" "main: exit 0"
expect_contains "$OUT" '"permissionDecision":"deny"' "main: deny"
expect_contains "$OUT" "protected branch 'main'" "main: names branch"
expect_contains "$OUT" '<issue>-<slug>' "main: issue form"
expect_contains "$OUT" 'docs/<slug>' "main: docs form"
expect_contains "$OUT" 'contract/<slug>' "main: contract form"
expect_contains "$OUT" 'never invent an issue number' "main: no invented issue"
if pyjson 'import json,sys;json.loads(sys.stdin.read())' <<<"$OUT" 2>/dev/null; then pass "main: output is valid JSON"; else fail "main: output is valid JSON"; fi

make_repo "$TMP/r-master" master
expect_deny "$(write_payload "$(cd "$TMP/r-master" && pwd)/a.txt")" "master"

make_repo "$TMP/r-trunk" trunk
git -C "$TMP/r-trunk" update-ref refs/remotes/origin/trunk HEAD
git -C "$TMP/r-trunk" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/trunk
run_hook "$(write_payload "$(cd "$TMP/r-trunk" && pwd)/a.txt")"
expect_contains "$OUT" "protected branch 'trunk'" "origin/HEAD default is protected"

echo "allowed branches"
for b in 41-x docs/x claude/brave-otter; do
  d="$TMP/r-$(printf '%s' "$b" | tr '/' '_')"
  make_repo "$d" "$b"
  expect_allow "$(write_payload "$(cd "$d" && pwd)/a.txt")" "branch $b"
done

echo "local branch listing"
make_repo "$TMP/r-list" main
git -C "$TMP/r-list" branch 12-a
git -C "$TMP/r-list" branch docs/x
git -C "$TMP/r-list" branch scratch
run_hook "$(write_payload "$(cd "$TMP/r-list" && pwd)/a.txt")"
expect_contains "$OUT" "12-a" "lists 12-a"
expect_contains "$OUT" "docs/x" "lists docs/x"
refute_contains "$OUT" "scratch" "does not list unrelated branch"

echo "Windows path forms (Review Focus 1)"
WIN="$(cd "$TMP/r-main" && pwd -W 2>/dev/null)"
if [ -n "$WIN" ] && [[ "$WIN" =~ ^[A-Za-z]: ]]; then
  BS="${WIN//\//\\}"
  expect_deny "$(write_payload "$BS\\src\\a.cs")" "backslash form"
  expect_deny "$(write_payload "$WIN/src/a.cs")" "D:/ form"
  expect_deny "$(write_payload "$(printf '/%s%s' "$(printf '%s' "${WIN:0:1}" | tr 'A-Z' 'a-z')" "${WIN:2}")/src/a.cs")" "/d/ form"
else
  echo "  skip - drive-letter path forms (not on Windows)"
fi

echo "edge locations"
mkdir -p "$TMP/norepo"
expect_allow "$(write_payload "$(cd "$TMP/norepo" && pwd)/a.txt")" "outside any repo"
expect_deny "$(write_payload "$RM/new/deep/er/a.cs")" "new file in missing subfolder of main repo"

make_repo "$TMP/r-det" main
git -C "$TMP/r-det" checkout -q --detach
expect_allow "$(write_payload "$(cd "$TMP/r-det" && pwd)/a.txt")" "detached HEAD"

mkdir -p "$TMP/r-unborn"; git -C "$TMP/r-unborn" init -q -b main
expect_allow "$(write_payload "$(cd "$TMP/r-unborn" && pwd)/a.txt")" "unborn branch"

echo "other tools"
run_hook "{\"tool_name\":\"NotebookEdit\",\"tool_input\":{\"notebook_path\":\"$RM/n.ipynb\"}}"
expect_contains "$OUT" '"permissionDecision":"deny"' "NotebookEdit notebook_path denied on main"
run_hook "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$RM/a.cs\",\"old_string\":\"a\",\"new_string\":\"b\"}}"
expect_contains "$OUT" '"permissionDecision":"deny"' "Edit denied on main"
expect_allow '{"tool_name":"Write","tool_input":{"content":"x"}}' "no path in payload"

echo "malformed input (Review Focus 5)"
expect_allow "" "empty stdin"
expect_allow "not json" "not json"

finish
