#!/usr/bin/env bash
# Tests: sdlc_command / sdlc_segments / sdlc_git_target (lib.sh) and guard-git (unsafe git, outward writes).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"
. "$HERE/fixtures.sh"
LIB="$ROOT/plugin/hooks/lib.sh"
HOOK="$ROOT/plugin/hooks/guard-git.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
. "$LIB"

NL=$'\n'

echo "sdlc_command"
SDLC_PAYLOAD='{"command":"decoy","tool_name":"Bash","tool_input":{"command":"git status"},"cwd":"/x"}'
expect_eq "$(sdlc_command)" "git status" "command read from tool_input, not an earlier top-level key"
SDLC_PAYLOAD='{"tool_input":{"description":"{\"command\":\"evil\"}","command":"git log"}}'
expect_eq "$(sdlc_command)" "git log" "escaped inner command key cannot shadow"
SDLC_PAYLOAD='{"tool_input":{"command":"git status\ngit push origin main"}}'
expect_eq "$(sdlc_command)" "git status${NL}git push origin main" "\\n becomes a newline"
SDLC_PAYLOAD='{"tool_input":{"command":"echo \"a\\nb\" C:\\new"}}'
expect_eq "$(sdlc_command)" 'echo "a\nb" C:\new' "escaped backslash before n stays a backslash"
SDLC_PAYLOAD='{"tool_input":{"command":"git commit -m \u0027x\u0027 \u0026\u0026 ls"}}'
expect_eq "$(sdlc_command)" "git commit -m 'x' && ls" "\\u0027 and \\u0026 decoded"
SDLC_PAYLOAD='{"tool_name":"Bash"}'
expect_empty "$(sdlc_command)" "no tool_input -> empty"

echo "sdlc_segments"
seg() { sdlc_segments "$1" | paste -sd'|' -; }
seg_raw() { sdlc_segments --raw "$1" | paste -sd'|' -; }
expect_eq "$(seg 'a && b || c; d | e')" "a|b|c|d|e" "splits on && || ; |"
expect_eq "$(seg "git status${NL}git push origin main")" "git status|git push origin main" "splits on newline"
expect_eq "$(seg 'git commit -m "document git push --force"')" 'git commit -m ""' "double-quoted text blanked"
expect_eq "$(seg "echo 'a && b; c'")" 'echo ""' "separators inside single quotes do not split"
expect_eq "$(seg 'echo "gh pr create"')" 'echo ""' "echo of a command is blanked"
expect_eq "$(seg 'env GIT_TRACE=1 git push -u origin 41-x')" "git push -u origin 41-x" "env VAR= stripped"
expect_eq "$(seg 'FOO=1 BAR="a b" sudo git push')" "git push" "VAR=value and sudo stripped"
expect_eq "$(seg 'command git push')" "git push" "command stripped"
expect_eq "$(seg 'env -u X git push')" "git push" "env -u X stripped"
expect_eq "$(seg 'if true; then git push origin main; fi')" "true|git push origin main|fi" "then stripped"
expect_eq "$(seg 'git status # git push origin main')" "git status" "comment dropped"
expect_eq "$(seg '(cd x && git push)')" "cd x|git push" "subshell parentheses split"
expect_eq "$(seg 'git push \
origin main')" "git push origin main" "line continuation joins"
case "$(seg "bash -c 'git push origin main'")" in *"git push origin main"*) pass "bash -c payload becomes a segment" ;; *) fail "bash -c payload becomes a segment" ;; esac
case "$(seg 'echo "$(git push origin main)"')" in *"git push origin main"*) pass "command substitution in double quotes becomes a segment" ;; *) fail "command substitution in double quotes becomes a segment" ;; esac
case "$(seg 'echo `git push origin main`')" in *"git push origin main"*) pass "backtick substitution becomes a segment" ;; *) fail "backtick substitution becomes a segment" ;; esac
expect_eq "$(seg_raw "gh api graphql -f query='mutation{x}'")" "gh api graphql -f query='mutation{x}'" "--raw keeps quoted text"
expect_eq "$(seg_raw 'FOO="a b" git commit -m "x y"')" 'git commit -m "x y"' "--raw strips prefix, keeps quotes"
expect_empty "$(sdlc_segments '')" "empty command -> no segments"
expect_eq "$(seg "cat <<'EOF'${NL}it's${NL}EOF${NL}git push origin main")" "cat|git push origin main" "heredoc body with an apostrophe is skipped"
expect_eq "$(seg "cat <<-EOF${NL}	x${NL}	EOF${NL}git push")" "cat|git push" "<<- heredoc with tab-indented terminator"
expect_eq "$(seg "cat <<EOF${NL}\$(git push origin main)${NL}EOF")" "cat|git push origin main" "unquoted heredoc body: substitutions are commands"
expect_eq "$(seg "bash <<'EOF'${NL}git push origin main${NL}EOF")" "bash|git push origin main" "heredoc feeding a shell: body is commands"
expect_eq "$(seg "cat <<EOF | bash${NL}git push origin main${NL}EOF")" "cat|bash|git push origin main" "heredoc piped to a shell: body is commands"
expect_eq "$(seg 'echo $((1<<2))
git push')" 'echo $|1<<2|git push' "arithmetic << is not a heredoc"
expect_eq "$(seg "echo don't; git push origin main")" "echo don't|git push origin main" "unmatched ' is literal"
expect_eq "$(seg 'echo "oops; git push origin main')" 'echo "oops|git push origin main' "unmatched \" is literal"
expect_eq "$(sdlc_segments --ps 'git commit -m "a`"b"; git push origin main' | paste -sd'|' -)" 'git commit -m ""|git push origin main' "PowerShell backtick escapes a quote"
expect_eq "$(sdlc_segments --ps "\$m = @'${NL}Don't${NL}'@${NL}git push" | paste -sd'|' -)" '$m = ""|git push' "PowerShell here-string skipped"

echo "sdlc_git_target"
expect_eq "$(sdlc_git_target 'git push origin main' /d/a/b)" "/d/a/b" "no -C -> cwd"
expect_eq "$(sdlc_git_target 'git -C ../r push origin main' /d/a/b)" "/d/a/r" "-C relative to cwd"
expect_eq "$(sdlc_git_target 'git -C /d/other push' /d/a/b)" "/d/other" "-C absolute"
expect_eq "$(sdlc_git_target 'git -C D:\other push' /d/a/b)" "/d/other" "-C Windows path"
expect_eq "$(sdlc_git_target 'git -C x -C y status' /d/a)" "/d/a/x/y" "-C is cumulative"
expect_eq "$(sdlc_git_target 'git -C "my dir" status' /d/a)" "/d/a/my dir" "-C quoted path"
expect_eq "$(sdlc_git_target 'git commit -C HEAD' /d/a)" "/d/a" "-C after the subcommand is not a path"
expect_eq "$(sdlc_git_target 'git -c user.name=x -C r status' /d/a)" "/d/a/r" "-c skipped, -C honoured"

[ -f "$HOOK" ] || { fail "guard-git.sh exists"; finish; }

# --- fixtures: built once ---------------------------------------------------
. "$HOOK"
make_repo "$TMP/rm" main
make_repo "$TMP/rx" 41-x
M="$(cd "$TMP/rm" && pwd)"
X="$(cd "$TMP/rx" && pwd)"
mkdir -p "$TMP/norepo"
N="$(cd "$TMP/norepo" && pwd)"

# jesc <var-name>: JSON-escape a variable in place (no forks).
jesc() {
  local v="${!1}"
  v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; v="${v//$'\t'/\\t}"; v="${v//$'\n'/\\n}"
  printf -v "$1" '%s' "$v"
}
payload() { # tool cwd command [agent]: sets PAYLOAD (no subshell)
  local c="$3" d="$2" agent=""
  jesc c; jesc d
  [ -n "$4" ] && agent=",\"agent_id\":\"$4\""
  printf -v PAYLOAD '{"tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"%s}' "$1" "$c" "$d" "$agent"
}

SUBMSG='subagents never push or write to GitHub; return your result to the orchestrator'

# Process spawns are slow on Windows: the table runs the hook body in-process (guard_git_main, one subshell per case)
# and cases are launched 8 at a time and verified afterwards; `check` cases and the smoke tests run the real script.
RES="$TMP/res"; mkdir -p "$RES"
NQ=0; Q_LABEL=(); Q_EXP=(); Q_SUBMSG=()
queue() { # label expected payload [expect-subagent-message] [proc]
  local i="$NQ"
  Q_LABEL[i]="$1"; Q_EXP[i]="$2"; Q_SUBMSG[i]="$4"
  if [ "$5" = proc ]; then
    ( printf '%s' "$3" | bash "$HOOK" >"$RES/$i.out" 2>/dev/null; echo $? >"$RES/$i.rc" ) &
  else
    ( trap "echo \$? >\"$RES/$i.rc\"" EXIT; guard_git_main <<<"$3" >"$RES/$i.out" 2>/dev/null ) &
  fi
  NQ=$((NQ + 1))
  if [ $((NQ % 8)) = 0 ]; then wait; fi
}
# checkp <label> <expected> <tool> <cwd> <command> [agent]: build the payload, then check.
checkp() { local l="$1" e="$2"; shift 2; payload "$@"; check "$l" "$e" "$PAYLOAD"; }
# check <label> <expected> <payload>: runs the real hook as a separate process (smoke and malformed-input cases).
check() { queue "$1" "$2" "$3" "" proc; }

settle() {
  wait
  local i out rc
  for ((i = 0; i < NQ; i++)); do
    out="$(cat "$RES/$i.out")"; rc="$(cat "$RES/$i.rc")"
    expect_eq "$rc" "0" "${Q_LABEL[i]}: exit 0"
    case "${Q_EXP[i]}" in
      allow) expect_empty "$out" "${Q_LABEL[i]}: allow (no output)" ;;
      deny) expect_contains "$out" '"permissionDecision":"deny"' "${Q_LABEL[i]}: deny" ;;
      ask)
        expect_contains "$out" '"permissionDecision":"ask"' "${Q_LABEL[i]}: ask"
        expect_contains "$out" '"permissionDecisionReason":"Outward action:' "${Q_LABEL[i]}: ask reason starts Outward action:" ;;
    esac
    if [ -n "${Q_SUBMSG[i]}" ]; then
      expect_contains "$out" "$SUBMSG" "${Q_LABEL[i]}: reason says subagents never push"
    fi
  done
}

# t <main> <subagent> <cwd> <command> [tool]
t() {
  local tool="${5:-Bash}" sm=""
  [ "$2" = deny ] && sm=1   # every subagent denial carries the "never push" instruction
  payload "$tool" "$3" "$4"; queue "main [$4]" "$1" "$PAYLOAD"
  payload "$tool" "$3" "$4" a1b2c3; queue "sub  [$4]" "$2" "$PAYLOAD" "$sm"
}

echo "smoke: the real script, one process per case"
checkp "smoke: push to main" deny Bash "$X" 'git push origin main'
checkp "smoke: push branch (main session)" ask Bash "$X" 'git push -u origin 41-x'
checkp "smoke: push branch (subagent)" deny Bash "$X" 'git push -u origin 41-x' a1b2c3
checkp "smoke: commit on branch" allow Bash "$X" 'git commit -m x'
checkp "smoke: PowerShell tool" deny PowerShell "$X" 'git add .; git push origin main'

echo "git push"
t deny deny "$X" 'git push origin main'
t deny deny "$X" 'git push origin HEAD:main'
t deny deny "$X" 'git push origin "main"'
t deny deny "$X" 'git push origin refs/heads/main'
t deny deny "$X" 'git push origin master'
t deny deny "$X" 'git push --force origin 41-x'
t deny deny "$X" 'git push -f'
t deny deny "$X" 'git push origin +41-x'
t deny deny "$X" 'git push -fu origin 41-x'
t deny deny "$X" 'git push --delete origin main'
t deny deny "$X" 'git push --no-verify origin 41-x'
t deny deny "$X" 'git push --mirror'
t ask deny "$X" 'git push --force-with-lease origin 41-x'
t ask deny "$X" 'git push -u origin 41-x'
t ask deny "$X" 'git push origin HEAD'
t ask deny "$X" 'git push'
t deny deny "$M" 'git push'
t deny deny "$M" 'git push origin HEAD'
t deny deny "$M" 'git push -u origin'
t ask deny "$M" 'git push origin 41-x'

echo "git commit"
t deny deny "$M" 'git commit -m x'
t allow allow "$X" 'git commit -m x'
t deny deny "$X" 'git commit --no-verify -m x'
t deny deny "$X" 'git commit -n -m x'
t allow allow "$X" 'git commit -m "-n"'
t allow allow "$X" 'git commit -m "document git push --force"'
t allow allow "$N" 'git commit -m x'

echo "gh writes"
t ask deny "$X" 'gh pr create --fill'
t ask deny "$X" 'gh pr merge 5'
t ask deny "$X" 'gh pr comment 5 -b x'
t ask deny "$X" 'gh issue create -t x -b y'
t ask deny "$X" 'gh issue comment 41 -b x'
t ask deny "$X" 'gh issue edit 41'
t ask deny "$X" 'gh label create x'
t ask deny "$X" 'gh api repos/o/r/issues -f title=x'
t ask deny "$X" 'gh api -X PATCH repos/o/r/issues/1'
t ask deny "$X" 'gh api repos/o/r/issues/1 --method DELETE'
t ask deny "$X" "gh api graphql -f query='mutation{x}'"
t ask deny "$X" 'gh -R o/r pr create --fill'

echo "gh reads"
t allow allow "$X" 'gh issue view 41'
t allow allow "$X" 'gh pr view 5 --comments'
t allow allow "$X" 'gh pr checks 5'
t allow allow "$X" 'gh pr list'
t allow allow "$X" 'gh api repos/o/r/issues/1'
t allow allow "$X" 'gh api -X GET repos/o/r/issues -f per_page=1'
t allow allow "$X" "gh api graphql -f query='query{viewer{login}}'"

echo "compound, wrapped and quoted (Review Focus 4)"
t deny deny "$X" 'cd ../r && git push origin main'
t deny deny "$X" 'git -C ../r push origin main'
t deny deny "$X" "cd $M && git commit -m x"
t deny deny "$X" "git -C $M commit -m x"
t allow allow "$M" "git -C $X commit -m x"
t allow allow "$M" "cd $X && git commit -m x"
t deny deny "$M" "cd $X && cd $M && git commit -m x"
t ask deny "$X" 'env GIT_TRACE=1 git push -u origin 41-x'
t ask deny "$X" 'GIT_TRACE=1 git push -u origin 41-x'
t ask deny "$X" 'sudo git push -u origin 41-x'
t deny deny "$X" "git status${NL}git push origin main"
t deny deny "$X" 'git add .; git push origin main' PowerShell
t ask deny "$X" 'git add .; git push -u origin 41-x' PowerShell
t ask deny "$X" 'gh pr create --fill; gh pr merge 5' PowerShell
t deny deny "$X" "bash -c 'git push origin main'"
t ask deny "$X" 'bash -c "git push -u origin 41-x"'
t deny deny "$X" 'echo "$(git push origin main)"'
t deny deny "$X" '/usr/bin/git push origin main'
t deny deny "$X" 'git.exe push origin main'
t allow allow "$X" 'echo "gh pr create"'
t allow allow "$X" "echo 'git push origin main'"
t allow allow "$X" 'git log'
t allow allow "$X" 'git status'
t allow allow "$X" 'git status # git push origin main'
t allow allow "$X" 'ls && git diff | head'
t ask deny "$X" 'git status && gh pr create --fill'

echo "heredocs, here-strings and unmatched quotes (fix round 1, finding 1)"
t deny deny "$X" "git commit -F - <<'EOF'${NL}Don't break things${NL}EOF${NL}git push origin main"
t deny deny "$X" "git commit -F - <<'EOF'${NL}Don't break things${NL}EOF${NL}git push --force origin 41-x"
t deny deny "$M" "cat > n.md <<'EOF'${NL}it's${NL}EOF${NL}git commit -m x"
t ask deny "$X" "\$m = @'${NL}Don't${NL}'@${NL}git commit -m \$m; git push -u origin 41-x" PowerShell
t deny deny "$X" "cat <<'EOF'${NL}it's${NL}EOF${NL}git push origin main && echo 'done'"
t deny deny "$X" "echo don't; git push origin main"
t deny deny "$X" 'echo "oops; git push origin main'
t deny deny "$X" "echo \$((1<<2))${NL}git push origin main"
t deny deny "$X" "bash <<'EOF'${NL}git push origin main${NL}EOF"
t ask deny "$X" "cat <<EOF | bash${NL}git push -u origin 41-x${NL}EOF"
t deny deny "$X" "cat <<EOF${NL}\$(git push origin main)${NL}EOF"
t allow allow "$X" "cat <<'EOF'${NL}git push origin main${NL}EOF"
t allow allow "$X" "git commit -F - <<'EOF'${NL}Don't break things${NL}EOF"
t allow allow "$X" 'git commit -m "it'"'"'s fine"'

echo "runner prefixes (finding 2)"
t ask deny "$X" 'echo main | xargs git push origin'
t ask deny "$X" 'git branch --show-current | xargs git push -u origin'
t ask deny "$X" 'timeout 60 git push -u origin 41-x'
t ask deny "$X" 'nice git push -u origin 41-x'
t deny deny "$X" 'find . -exec git push origin main \;'
t deny deny "$X" 'eval git push origin main'
t deny deny "$X" 'cmd /c git push origin main'
t ask deny "$X" 'xargs gh pr create --fill'
t allow allow "$X" 'echo git push origin main'
t allow allow "$X" 'ls git'

echo "Windows program paths and case (finding 3)"
t deny deny "$X" '"C:\Program Files\Git\cmd\git.exe" push origin main'
t ask deny "$X" '& "C:\Program Files\Git\cmd\git.exe" push -u origin 41-x' PowerShell
t ask deny "$X" 'C:\tools\gh.exe pr create --fill'
t deny deny "$X" 'Git push origin main'
t deny deny "$X" 'git.EXE push origin main'
t ask deny "$X" 'GH pr create --fill'

echo "PowerShell backtick-escaped quote (finding 4)"
t deny deny "$X" 'git commit -m "a`"b"; git push origin main' PowerShell
t allow allow "$X" 'git commit -m "a`"b"' PowerShell

echo "Windows cwd form"
WINM="$(cd "$TMP/rm" && pwd -W 2>/dev/null)"
if [ -n "$WINM" ] && [[ "$WINM" =~ ^[A-Za-z]: ]]; then
  checkp "backslash cwd on main" deny Bash "${WINM//\//\\}" 'git commit -m x'
  checkp "D:/ cwd on main" deny Bash "$WINM" 'git commit -m x'
else
  echo "  skip - drive-letter cwd forms (not on Windows)"
fi

echo "edge locations"
t deny deny "$N" 'git push origin main'
t ask deny "$N" 'git push origin 41-x'

echo "malformed input (Review Focus 5)"
check "empty stdin" allow ""
check "not json" allow "not json"
check "no command" allow '{"tool_name":"Bash","tool_input":{}}'
check "command not a string" allow '{"tool_name":"Bash","tool_input":{"command":5}}'
checkp "non-git command" allow Bash "$X" 'ls -la'
check "decoy command key before tool_input" ask \
  '{"command":"ls","tool_name":"Bash","tool_input":{"command":"git push -u origin 41-x"},"cwd":"'"$X"'"}'

settle
finish
