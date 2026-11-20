#!/usr/bin/env bash
# Shared library for scrimpify-sdlc hooks. Source it; pure bash + git + coreutils.
# Every function documents its contract in the comment above it.

# sdlc_read_payload: read stdin into SDLC_PAYLOAD with newlines/CRs removed; return 1 if empty.
sdlc_read_payload() {
  SDLC_PAYLOAD="$(cat | tr -d '\r\n')"
  [ -n "$SDLC_PAYLOAD" ]
}

# sdlc_json_str <key>: print the first string value of "<key>":"..." in SDLC_PAYLOAD, unescaping \" and \\.
sdlc_json_str() {
  printf '%s' "$SDLC_PAYLOAD" \
    | grep -o -E "\"$1\"[[:space:]]*:[[:space:]]*\"([^\"\\\\]|\\\\.)*\"" \
    | head -n 1 \
    | sed -E -e "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//" -e 's/"$//' \
    | sed -e 's/\\\\/\x01/g' -e 's/\\"/"/g' -e 's/\x01/\\/g'
}

# sdlc_json_escape: stdin -> JSON-safe string body (escapes \ " tab; newline -> \n; CR dropped).
sdlc_json_escape() {
  tr -d '\r' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
    | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}

# sdlc_decide <deny|ask> <reason>: print a PreToolUse decision JSON on stdout (callers then exit 0).
sdlc_decide() {
  local reason
  reason="$(printf '%s' "$2" | sdlc_json_escape)"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$reason"
}

# sdlc_is_subagent: return 0 when SDLC_PAYLOAD carries a non-empty agent_id.
sdlc_is_subagent() {
  [ -n "$(sdlc_json_str agent_id)" ]
}

# sdlc_to_posix_path <path>: normalise to forward slashes and Git Bash drive form (D:\a\b -> /d/a/b).
sdlc_to_posix_path() {
  local p="${1//\\//}"
  while [[ "$p" == *//* ]]; do p="${p//\/\///}"; done
  if [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]]; then
    local d="${BASH_REMATCH[1]}"
    p="/${d,,}${BASH_REMATCH[2]}"
  fi
  printf '%s' "$p"
}

# sdlc_repo_of <path>: print the git top level (posix form) of the nearest existing ancestor dir, or nothing.
sdlc_repo_of() {
  local d top
  d="$(sdlc_to_posix_path "$1")"
  while [ -n "$d" ] && [ ! -d "$d" ]; do
    case "$d" in */*) d="${d%/*}" ;; *) d="" ;; esac
  done
  [ -n "$d" ] || d="/"
  [ -d "$d" ] || return 0
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 0
  sdlc_to_posix_path "$top"
}

# sdlc_collapse_path <posix-path>: drop empty and "." segments and resolve ".." lexically (no filesystem access).
sdlc_collapse_path() {
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
  printf '%s%s' "$lead" "${out[*]}"
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
