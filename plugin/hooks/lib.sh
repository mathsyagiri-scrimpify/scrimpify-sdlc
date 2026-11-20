#!/usr/bin/env bash
# Shared library for scrimpify-sdlc hooks. Source it; pure bash + git + coreutils.
# Every function documents its contract in the comment above it.

# sdlc_read_payload: read stdin into SDLC_PAYLOAD with newlines/CRs removed; return 1 if empty.
sdlc_read_payload() {
  IFS= read -r -d '' SDLC_PAYLOAD || true
  SDLC_PAYLOAD="${SDLC_PAYLOAD//$'\r'/}"
  SDLC_PAYLOAD="${SDLC_PAYLOAD//$'\n'/}"
  [ -n "$SDLC_PAYLOAD" ]
}

# sdlc_json_str <key>: print the first string value of "<key>":"..." in SDLC_PAYLOAD, unescaping \" and \\.
sdlc_json_str() {
  _sdlc_json_get "$1"
  printf '%s' "$REPLY"
}

# _sdlc_json_get <key>: sdlc_json_str that sets REPLY instead of printing (no subshell; forks are slow on Windows).
_sdlc_json_get() {
  REPLY=""
  local re="\"$1\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"" v b=$'\x01'
  [[ "$SDLC_PAYLOAD" =~ $re ]] || return 0
  v="${BASH_REMATCH[1]}"
  v="${v//\\\\/$b}"; v="${v//\\\"/\"}"
  REPLY="${v//$b/\\}"
}

# sdlc_json_escape: stdin -> JSON-safe string body (escapes \ " tab; newline -> \n; CR dropped).
sdlc_json_escape() {
  tr -d '\r' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
    | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}

# sdlc_decide <deny|ask> <reason>: print a PreToolUse decision JSON on stdout (callers then exit 0).
sdlc_decide() {
  local r="$2"
  r="${r//$'\r'/}"; r="${r//\\/\\\\}"; r="${r//\"/\\\"}"; r="${r//$'\t'/\\t}"; r="${r//$'\n'/\\n}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$r"
}

# sdlc_is_subagent: return 0 when SDLC_PAYLOAD carries a non-empty agent_id.
sdlc_is_subagent() {
  [ -n "$(sdlc_json_str agent_id)" ]
}

# sdlc_to_posix_path <path>: normalise to forward slashes and Git Bash drive form (D:\a\b -> /d/a/b).
sdlc_to_posix_path() {
  _sdlc_posix "$1"
  printf '%s' "$REPLY"
}

# _sdlc_posix <path>: sdlc_to_posix_path that sets REPLY (no subshell).
_sdlc_posix() {
  local p="${1//\\//}"
  while [[ "$p" == *//* ]]; do p="${p//\/\///}"; done
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local d="${BASH_REMATCH[1]}"
    p="/${d,,}${BASH_REMATCH[2]}"
  fi
  REPLY="$p"
}

# sdlc_repo_of <path>: print the git top level (posix form) of the nearest existing ancestor dir, or nothing.
sdlc_repo_of() {
  local d top
  _sdlc_posix "$1"; d="$REPLY"
  while [ -n "$d" ] && [ ! -d "$d" ]; do
    case "$d" in */*) d="${d%/*}" ;; *) d="" ;; esac
  done
  [ -n "$d" ] || d="/"
  [ -d "$d" ] || return 0
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 0
  _sdlc_posix "$top"; printf '%s' "$REPLY"
}

# sdlc_collapse_path <posix-path>: drop empty and "." segments and resolve ".." lexically (no filesystem access).
sdlc_collapse_path() {
  _sdlc_collapse "$1"
  printf '%s' "$REPLY"
}

# _sdlc_collapse <posix-path>: sdlc_collapse_path that sets REPLY (no subshell).
_sdlc_collapse() {
  local p="$1" lead="" seg out=()
  case "$p" in /*) lead="/" ;; esac
  local segs; IFS=/ read -r -a segs <<< "$p"
  local IFS=/
  for seg in "${segs[@]}"; do
    case "$seg" in
      ""|.) ;;
      ..) if [ "${#out[@]}" -gt 0 ] && [ "${out[${#out[@]}-1]}" != ".." ]; then unset 'out[${#out[@]}-1]'; elif [ -z "$lead" ]; then out+=(..); fi ;;
      *) out+=("$seg") ;;
    esac
  done
  REPLY="$lead${out[*]}"
}

# sdlc_rel_path <repo> <abs-path>: print abs-path (with . and .. collapsed) relative to repo; empty if outside.
sdlc_rel_path() {
  local repo p lr lp
  repo="$(sdlc_collapse_path "$(sdlc_to_posix_path "$1")")"
  p="$(sdlc_collapse_path "$(sdlc_to_posix_path "$2")")"
  lr="${repo,,}"; lp="${p,,}"
  case "$lp" in
    "$lr"/*) printf '%s' "${p:$((${#repo} + 1))}" ;;
  esac
  return 0
}

# sdlc_branch <repo>: print the current branch name; empty when detached or none.
sdlc_branch() {
  git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true
}

# sdlc_protected <repo>: print protected branch names, one per line: main, master, origin/HEAD's default.
sdlc_protected() {
  local def
  printf 'main\nmaster\n'
  def="$(git -C "$1" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)" || return 0
  def="${def#origin/}"
  case "$def" in ""|main|master) ;; *) printf '%s\n' "$def" ;; esac
  return 0
}

# sdlc_command: print the Bash/PowerShell command from SDLC_PAYLOAD's tool_input (JSON escapes decoded, \n -> newline); empty if none.
sdlc_command() {
  _sdlc_command_get
  printf '%s' "$REPLY"
}

# _sdlc_command_get: sdlc_command that sets REPLY (no subshell). Only the text after "tool_input" is searched,
# so an earlier top-level "command" key cannot shadow it.
_sdlc_command_get() {
  REPLY=""
  local rest="${SDLC_PAYLOAD#*\"tool_input\"}" v b=$'\x01'
  [ "$rest" != "$SDLC_PAYLOAD" ] || return 0
  [[ "$rest" =~ \"command\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] || return 0
  v="${BASH_REMATCH[1]}"
  v="${v//\\\\/$b}"
  v="${v//\\n/$'\n'}"; v="${v//\\t/$'\t'}"; v="${v//\\r/}"
  v="${v//\\\"/\"}"; v="${v//\\\//\/}"
  v="${v//\\u0027/\'}"; v="${v//\\u0026/\&}"; v="${v//\\u003c/<}"; v="${v//\\u003e/>}"; v="${v//\\u0060/\`}"
  REPLY="${v//$b/\\}"
}

read -r -d '' SDLC_SEG_AWK <<'AWK' || true
BEGIN { RS = "\001" }
{ process($0) }

# process(s): split s into command segments (quote-aware) and flush each one.
# Heredoc bodies and PowerShell here-strings are skipped as text (or processed as commands when they feed a shell);
# an unmatched quote is a literal character, never "the rest of the command".
function process(s,   len, i, j, k, c, d, ct, u, nt, nq, bc, rc, btok, rtok, qs, nh, hterm, hdash_a, hquot_a, sl, e, q, pos, body) {
  len = length(s); nt = 0; nq = 0; bc = ""; rc = ""; nh = 0
  for (i = 1; i <= len; i++) {
    c = substr(s, i, 1)
    if (c == "\\" && !ps) {
      d = substr(s, i + 1, 1)
      if (d == "\n") { i++; continue }
      bc = bc c d; rc = rc c d; i++
      continue
    }
    if (ps && c == "`") {
      d = substr(s, i + 1, 1)
      if (d == "\n") { i++; continue }
      bc = bc c d; rc = rc c d; i++
      continue
    }
    if (ps && c == "@" && bc == "" && (substr(s, i + 1, 1) == "'" || substr(s, i + 1, 1) == "\"")) {
      q = substr(s, i + 1, 1)
      pos = index(substr(s, i + 2), "\n")
      if (pos > 0 && substr(s, i + 2, pos - 1) ~ /^[ \t\r]*$/) {
        ct = substr(s, i + 2 + pos)
        k = index("\n" ct, "\n" q "@")
        if (k > 0) { body = substr(ct, 1, k - 2); i = i + 2 + pos + k - 1 + 1 }
        else { body = ct; i = len }
        if (q == "\"") substs(body)
        gsub(/\n/, " ", body); gsub(/"/, "'", body); gsub(/\\/, "/", body)
        bc = bc "\"\""; rc = rc "\"" body "\""
        continue
      }
    }
    if (!ps && c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<") {
      parse_heredoc(s, i)
      if (HOK) { nh++; hterm[nh] = HW; hdash_a[nh] = HD; hquot_a[nh] = HQ; i = HEND - 1; continue }
    }
    if (c == "'") {
      j = index(substr(s, i + 1), "'")
      if (j == 0) { bc = bc c; rc = rc c; continue }
      ct = substr(s, i + 1, j - 1); i = i + j
      gsub(/\n/, " ", ct)
      bc = bc "\"\""; rc = rc "'" ct "'"; qs[++nq] = ct
      continue
    }
    if (c == "\"") {
      ct = ""; j = i + 1; k = 0
      while (j <= len) {
        d = substr(s, j, 1)
        if (d == "\\" && !ps) { ct = ct d substr(s, j + 1, 1); j += 2; continue }
        if (d == "`" && ps) { ct = ct d substr(s, j + 1, 1); j += 2; continue }
        if (d == "$" && substr(s, j + 1, 1) == "(") {
          # a command substitution is parsed as its own command (quotes and heredocs inside it are its own)
          e = findclose(s, j + 2)
          process(substr(s, j + 2, e - (j + 2)))
          ct = ct "$()"; j = e + 1
          continue
        }
        if (d == "\"") { k = 1; break }
        ct = ct d; j++
      }
      if (!k) { bc = bc c; rc = rc c; continue }
      i = j
      substs(ct)
      gsub(/\n/, " ", ct)
      bc = bc "\"\""; rc = rc "\"" ct "\""
      u = ct
      if (ps) gsub(/`"/, "\"", u); else gsub(/\\"/, "\"", u)
      qs[++nq] = u
      continue
    }
    if (c == "#" && bc == "") {
      while (i < len && substr(s, i + 1, 1) != "\n") i++
      continue
    }
    if (c == " " || c == "\t") {
      if (bc != "") { btok[++nt] = bc; rtok[nt] = rc; bc = ""; rc = "" }
      continue
    }
    if (c == "&" || c == "|" || c == ";" || c == "\n" || c == "(" || c == ")" || (!ps && c == "`")) {
      if (bc != "") { btok[++nt] = bc; rtok[nt] = rc; bc = ""; rc = "" }
      flush(nt, btok, rtok, nq, qs)
      nt = 0; nq = 0; split("", btok); split("", rtok); split("", qs)
      if (c == "\n") {
        if (nh > 0) {
          pos = i + 1; sl = shellline
          for (k = 1; k <= nh; k++) {
            body = heredoc_body(s, pos, hterm[k], hdash_a[k])
            pos = HPOS
            if (sl) process(body)
            else if (!hquot_a[k]) substs(body)
          }
          i = pos - 1
          nh = 0
        }
        shellline = 0
      }
      continue
    }
    bc = bc c; rc = rc c
  }
  if (bc != "") { btok[++nt] = bc; rtok[nt] = rc }
  flush(nt, btok, rtok, nq, qs)
  shellline = 0
}

# parse_heredoc(s, i): s[i..i+1] is "<<". Sets HOK (a heredoc really starts), HW (delimiter), HQ (delimiter quoted: body is
# literal), HD (<<-), HEND (index just after the delimiter word). A digit-led word (arithmetic 1<<2) is not a heredoc.
function parse_heredoc(s, i,   j, d, q, wst, len) {
  len = length(s); j = i + 2; HD = 0
  if (substr(s, j, 1) == "-") { HD = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  HW = ""; HQ = 0; wst = substr(s, j, 1)
  while (j <= len) {
    d = substr(s, j, 1)
    if (d == "'" || d == "\"") {
      HQ = 1; q = d; j++
      while (j <= len && substr(s, j, 1) != q) { HW = HW substr(s, j, 1); j++ }
      j++
      continue
    }
    if (d == "\\") { HQ = 1; j++; continue }
    if (d == " " || d == "\t" || d == "\n" || d == ";" || d == "&" || d == "|" || d == "(" || d == ")" || d == "<" || d == ">") break
    HW = HW d; j++
  }
  HEND = j
  HOK = (HW != "" && (wst == "'" || wst == "\"" || wst == "\\" || wst ~ /[A-Za-z_]/))
}

# heredoc_body(s, pos, term, dash): return the body lines starting at pos up to the terminator line (a <<- terminator may
# be tab-indented); sets HPOS to the index after the terminator line.
function heredoc_body(s, pos, term, dash,   len, ln, line, nl, u, body) {
  len = length(s); body = ""
  while (pos <= len) {
    ln = index(substr(s, pos), "\n")
    if (ln == 0) { line = substr(s, pos); nl = len + 1 } else { line = substr(s, pos, ln - 1); nl = pos + ln }
    u = line
    if (dash) sub(/^\t+/, "", u)
    pos = nl
    if (u == term) break
    body = body line "\n"
  }
  HPOS = pos
  return body
}

# findclose(s, p): p is just after "$(". Return the index of the matching ")" (len+1 if none), skipping quoted strings,
# nested substitutions and heredoc bodies.
function findclose(s, p,   len, d, depth, j, k, nh, ht, hd, pos) {
  len = length(s); depth = 1; nh = 0
  for (j = p; j <= len; j++) {
    d = substr(s, j, 1)
    if ((d == "\\" && !ps) || (d == "`" && ps)) { j++; continue }
    if (d == "'") { k = index(substr(s, j + 1), "'"); if (k == 0) return len + 1; j += k; continue }
    if (d == "\"") { j = dqend(s, j + 1); continue }
    if (!ps && d == "<" && substr(s, j + 1, 1) == "<" && substr(s, j + 2, 1) != "<") {
      parse_heredoc(s, j)
      if (HOK) { nh++; ht[nh] = HW; hd[nh] = HD; j = HEND - 1; continue }
    }
    if (d == "\n" && nh > 0) {
      pos = j + 1
      for (k = 1; k <= nh; k++) { heredoc_body(s, pos, ht[k], hd[k]); pos = HPOS }
      j = pos - 1; nh = 0
      continue
    }
    if (d == "(") depth++
    else if (d == ")") { depth--; if (depth == 0) return j }
  }
  return len + 1
}

# dqend(s, p): p is just after an opening ". Return the index of the closing " (len+1 if none), skipping $(...).
function dqend(s, p,   len, j, d) {
  len = length(s)
  for (j = p; j <= len; j++) {
    d = substr(s, j, 1)
    if ((d == "\\" && !ps) || (d == "`" && ps)) { j++; continue }
    if (d == "$" && substr(s, j + 1, 1) == "(") { j = findclose(s, j + 2); continue }
    if (d == "\"") return j
  }
  return len + 1
}

# substs(ct): process $(...) and `...` found inside a double-quoted string as their own commands.
function substs(ct,   t, i, d, j, c, e) {
  t = ct
  while ((i = index(t, "$(")) > 0) {
    d = 1; j = i + 2
    while (j <= length(t) && d > 0) {
      c = substr(t, j, 1)
      if (c == "(") d++
      else if (c == ")") d--
      j++
    }
    if (d == 0) e = j - 2; else e = j - 1
    process(substr(t, i + 2, e - (i + 2) + 1))
    t = substr(t, j)
  }
  t = ct
  while ((i = index(t, "`")) > 0) {
    j = index(substr(t, i + 1), "`")
    if (j == 0) break
    process(substr(t, i + 1, j - 1))
    t = substr(t, i + j + 1)
  }
}

# flush: strip leading wrappers, print the segment, and descend into `sh -c "..."`-style payloads.
function flush(nt, btok, rtok, nq, qs,   st, t, i, b, r, sl0) {
  st = 1
  while (st <= nt) {
    t = btok[st]
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { st++; continue }
    if (t ~ /^(then|do|else|elif|if|while|until|time|nohup|exec|command|builtin|!|\{)$/) { st++; continue }
    if (t == "env" || t == "sudo") {
      st++
      while (st <= nt && btok[st] ~ /^-/) { if (btok[st] ~ /^-(u|g|C|S)$/) st++; st++ }
      continue
    }
    break
  }
  if (st > nt) return
  b = btok[st]; r = rtok[st]
  for (i = st + 1; i <= nt; i++) { b = b " " btok[i]; r = r " " rtok[i] }
  if (raw) print r; else print b
  if (btok[st] ~ "^(.*[\\\\/])?(bash|sh|zsh|dash|ksh|eval|pwsh|powershell|cmd)(\\.exe)?$") {
    shellline = 1
    sl0 = shellline
    for (i = 1; i <= nq; i++) process(qs[i])
    shellline = sl0
  }
}
AWK

# sdlc_segments [--raw] [--ps] <command>: one segment per line, quote-aware split on && || ; | & newline ( ) and backtick;
# quoted strings become "" (or stay intact with --raw); leading env/VAR=x/sudo/command/then/... stripped;
# $(...) and `...` inside double quotes, and the payload of `bash -c "..."`, become segments too.
sdlc_segments() {
  local raw=0 ps=0
  while :; do
    case "$1" in --raw) raw=1 ;; --ps) ps=1 ;; *) break ;; esac
    shift
  done
  [ -n "$1" ] || return 0
  printf '%s' "$1" | awk -v raw="$raw" -v ps="$ps" "$SDLC_SEG_AWK"
}

# sdlc_resolve_dir <base> <path>: print a posix, lexically collapsed path; <path> is taken relative to <base> unless absolute.
sdlc_resolve_dir() {
  _sdlc_resolve "$1" "$2"
  printf '%s' "$REPLY"
}

# _sdlc_resolve <base> <path>: sdlc_resolve_dir that sets REPLY (no subshell).
_sdlc_resolve() {
  local base="$1" p
  _sdlc_posix "$2"; p="$REPLY"
  case "$p" in
    /*) ;;
    *) if [ -n "$base" ]; then _sdlc_posix "$base"; p="$REPLY/$p"; fi ;;
  esac
  _sdlc_collapse "$p"
}

# sdlc_words <segment>: split a segment into shell words; sets arrays SDLC_WR (as written, quotes kept) and SDLC_W (quotes removed).
sdlc_words() {
  SDLC_WR=(); SDLC_W=()
  local rest="$1" tok dq sq re
  dq='"([^"\\]|\\.)*"'
  sq="'[^']*'"
  re="^[[:space:]]*((${dq}|${sq}|\\\\.|[^[:space:]'\"\\\\])+)"
  while [[ "$rest" =~ $re ]]; do
    tok="${BASH_REMATCH[1]}"
    rest="${rest:${#BASH_REMATCH[0]}}"
    SDLC_WR+=("$tok")
    tok="${tok//\"/}"; tok="${tok//\'/}"
    SDLC_W+=("$tok")
  done
}

# sdlc_git_parse <git-segment>: runs sdlc_words, then sets SDLC_GC (the -C paths, in order) and SDLC_GI (index of the
# subcommand in SDLC_W, after git's own global options).
sdlc_git_parse() {
  sdlc_words "$1"
  SDLC_GC=()
  local n="${#SDLC_W[@]}" i=1 w
  while [ "$i" -lt "$n" ]; do
    w="${SDLC_WR[$i]}"
    case "$w" in
      -C) SDLC_GC+=("${SDLC_W[$((i + 1))]}"); i=$((i + 2)) ;;
      -c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  SDLC_GI=$i
}

# sdlc_git_target <git-segment> <cwd>: print the directory (posix) the git command acts on: cwd, moved by each global -C.
sdlc_git_target() {
  local dir c
  _sdlc_posix "$2"; dir="$REPLY"
  sdlc_git_parse "$1"
  for c in "${SDLC_GC[@]}"; do _sdlc_resolve "$dir" "$c"; dir="$REPLY"; done
  printf '%s' "$dir"
}
