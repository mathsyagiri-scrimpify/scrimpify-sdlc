#!/usr/bin/env bash
# PreToolUse hook (Bash and PowerShell): deny unsafe git, ask before outward GitHub/git writes,
# and deny those outward writes outright for subagents (they never push or post).
# Allow = exit 0 with no output. Unparseable or empty input also allows.
# Forks are slow on Windows, so this file avoids command substitution where it can.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SUBMSG="subagents never push or write to GitHub; return your result to the orchestrator"

# quote <segment>: sets Q to the segment, shortened, for use inside a reason.
quote() {
  Q="$1"
  [ "${#Q}" -le 200 ] || Q="${Q:0:200}..."
}

# block <rule> <segment>: deny, naming the rule (subagents also get the "never push" instruction).
block() {
  quote "$2"
  if [ -n "$SUB" ]; then
    sdlc_decide deny "Blocked by guard-git: $1. Segment: \`$Q\`. $SUBMSG."
  else
    sdlc_decide deny "Blocked by guard-git: $1. Segment: \`$Q\`."
  fi
  exit 0
}

# outward <what> <segment>: ask in the main session; deny for a subagent.
outward() {
  quote "$2"
  if [ -n "$SUB" ]; then
    sdlc_decide deny "Blocked outward action \`$Q\` ($1): $SUBMSG."
  else
    sdlc_decide ask "Outward action: \`$Q\` ($1). Confirm to run it."
  fi
  exit 0
}

REPO=""; BRANCH=""; BRANCH_KNOWN=0; PROT=""; PROT_KNOWN=0

# set_repo <dir>: point REPO at the nearest existing ancestor of <dir> (git -C works from any subfolder);
# reset the branch and protected-name caches. REPO is empty when there is no such directory.
set_repo() {
  local d="$1"
  while [ -n "$d" ] && [ ! -d "$d" ]; do
    case "$d" in */*) d="${d%/*}" ;; *) d="" ;; esac
  done
  REPO="$d"
  BRANCH=""; BRANCH_KNOWN=0; PROT=""; PROT_KNOWN=0
}

# current_branch: set BRANCH lazily (empty when detached, unborn or no repo).
current_branch() {
  [ "$BRANCH_KNOWN" = 0 ] || return 0
  BRANCH_KNOWN=1
  [ -n "$REPO" ] && BRANCH="$(git -C "$REPO" symbolic-ref --short -q HEAD 2>/dev/null)"
  return 0
}

# is_protected <name>: true if <name> is a protected branch of REPO (main/master always count).
is_protected() {
  case "$1" in main|master) return 0 ;; esac
  if [ "$PROT_KNOWN" = 0 ]; then
    PROT_KNOWN=1
    PROT=""
    if [ -n "$REPO" ]; then
      PROT="$(git -C "$REPO" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)"
      PROT="${PROT#origin/}"
    fi
  fi
  [ -n "$PROT" ] && [ "$PROT" = "$1" ]
}

handle_push() { # seg
  local seg="$1" k n="${#SDLC_W[@]}" wr w skip=0
  local force=0 noverify=0 mirror=0 pos=()
  for ((k = SDLC_GI + 1; k < n; k++)); do
    wr="${SDLC_WR[$k]}"; w="${SDLC_W[$k]}"
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$wr" in
      --force|-f) force=1 ;;
      --force-with-lease|--force-with-lease=*|--force-if-includes) ;;
      --no-verify) noverify=1 ;;
      --mirror|--all) mirror=1 ;;
      -o|--push-option|--repo|--receive-pack|--exec) skip=1 ;;
      --*) ;;
      -*) [[ "$wr" =~ ^-[a-zA-Z]*f[a-zA-Z]*$ ]] && force=1 ;;
      *) pos+=("$w") ;;
    esac
  done
  [ "$noverify" = 0 ] || block "git push --no-verify skips the pre-push checks" "$seg"
  [ "$force" = 0 ] || block "force push is not allowed (use --force-with-lease only for your own branch)" "$seg"
  [ "$mirror" = 0 ] || block "git push --mirror/--all can overwrite or push protected branches" "$seg"

  local p dest
  for p in "${pos[@]:1}"; do
    case "$p" in +*) block "force push (+refspec) is not allowed" "$seg" ;; esac
  done
  for p in "${pos[@]:1}"; do
    case "$p" in *:*) dest="${p#*:}" ;; *) dest="$p" ;; esac
    dest="${dest#refs/heads/}"
    if [ "$dest" = HEAD ] || [ "$dest" = "@" ]; then current_branch; dest="$BRANCH"; fi
    if [ -n "$dest" ] && is_protected "$dest"; then
      block "never push to protected branch '$dest'; work on an issue branch and open a PR" "$seg"
    fi
  done
  if [ "${#pos[@]}" -le 1 ]; then
    current_branch
    if [ -n "$BRANCH" ] && is_protected "$BRANCH"; then
      block "never push protected branch '$BRANCH'; work on an issue branch and open a PR" "$seg"
    fi
  fi
  outward "git push" "$seg"
}

handle_commit() { # seg
  local seg="$1" k n="${#SDLC_W[@]}" wr
  for ((k = SDLC_GI + 1; k < n; k++)); do
    wr="${SDLC_WR[$k]}"
    case "$wr" in
      --no-verify) block "git commit --no-verify skips the commit hooks" "$seg" ;;
      --*) ;;
      -*) [[ "$wr" =~ ^-[a-zA-Z]*n[a-zA-Z]*$ ]] && block "git commit -n (--no-verify) skips the commit hooks" "$seg" ;;
    esac
  done
  current_branch
  if [ -n "$BRANCH" ] && is_protected "$BRANCH"; then
    # A first commit on an unborn branch has nothing to protect yet.
    git -C "$REPO" rev-parse --verify -q HEAD >/dev/null 2>&1 || return 0
    block "never commit on protected branch '$BRANCH'; create an issue branch first" "$seg"
  fi
}

handle_git() { # seg
  local seg="$1" dir c sub
  dir="$cur"
  sdlc_git_parse "$seg"
  for c in "${SDLC_GC[@]}"; do _sdlc_resolve "$dir" "$c"; dir="$REPLY"; done
  sub="${SDLC_W[$SDLC_GI]}"
  case "$sub" in
    push) set_repo "$dir"; handle_push "$seg" ;;
    commit) set_repo "$dir"; handle_commit "$seg" ;;
  esac
}

# in_list <word> <list...>: true if <word> is one of the list items.
in_list() {
  local w="$1" x; shift
  for x in "$@"; do [ "$x" = "$w" ] && return 0; done
  return 1
}

handle_api() { # seg  (SDLC_W/SDLC_WR hold the words of "gh api ...")
  local seg="$1" k n="${#SDLC_W[@]}" wr w method="" fields=0 endpoint="" skip=0
  for ((k = 2; k < n; k++)); do
    wr="${SDLC_WR[$k]}"; w="${SDLC_W[$k]}"
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$wr" in
      -X|--method) method="${SDLC_W[$((k + 1))]}"; skip=1 ;;
      --method=*) method="${w#--method=}" ;;
      -X?*) method="${w#-X}" ;;
      -f|-F|--field|--raw-field|--input) fields=1; skip=1 ;;
      --field=*|--raw-field=*|--input=*) fields=1 ;;
      -f?*|-F?*) fields=1 ;;
      -H|--header|-q|--jq|-t|--template|-p|--preview|--cache|--hostname) skip=1 ;;
      -*) ;;
      *) [ -n "$endpoint" ] || endpoint="$w" ;;
    esac
  done
  method="${method^^}"
  if [ "$endpoint" = graphql ]; then
    # Read the query from the raw segment: a mutation writes; a query file or --input cannot be inspected.
    local low="${seg,,}"
    if [[ "$low" =~ (^|[^a-z0-9_])mutation([^a-z0-9_]|$) ]] || [[ "$low" =~ query=@ ]] || [[ "$low" =~ --input ]]; then
      outward "gh api graphql mutation" "$seg"
    fi
    return 0
  fi
  case "$method" in
    POST|PUT|PATCH|DELETE) outward "gh api $method" "$seg" ;;
    GET|HEAD) return 0 ;;
  esac
  [ "$fields" = 0 ] || outward "gh api with request fields (implicit POST)" "$seg"
  return 0
}

handle_gh() { # seg
  sdlc_words "$1"   # the segment may start at a later word of the original (runner prefix)
  local seg="$1" k n="${#SDLC_W[@]}" wr skip=0 pos=()
  for ((k = 1; k < n; k++)); do
    wr="${SDLC_WR[$k]}"
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    case "$wr" in
      -R|--repo) skip=1 ;;
      -*) ;;
      *) pos+=("${SDLC_W[$k]}") ;;
    esac
  done
  local group="${pos[0]}" verb="${pos[1]}"
  case "$group" in
    api)
      # Re-index so "api" is word 1 even when -R/--repo came first.
      sdlc_words "gh api ${seg#*api}"
      handle_api "$seg" ;;
    pr) in_list "$verb" view list status diff checks checkout || outward "gh pr $verb" "$seg" ;;
    issue) in_list "$verb" view list status || outward "gh issue $verb" "$seg" ;;
    repo|release|run|workflow|label|gist|secret|variable|ssh-key|gpg-key|cache|codespace|ruleset|project|org)
      in_list "$verb" view list status get check clone download watch field-list item-list || outward "gh $group $verb" "$seg" ;;
  esac
  return 0
}

# wbase <word>: set REPLY to the lowercase program name of <word> (directories and .exe dropped; \ or / separators).
wbase() {
  local b="${1##*[\\/]}"
  b="${b,,}"
  REPLY="${b%.exe}"
}

# guard_git_main: the hook body; reads the payload from stdin and prints a decision or nothing (callers then exit 0).
guard_git_main() {
  sdlc_read_payload || exit 0
  _sdlc_command_get
  local cmd="$REPLY" i seg base rest segopt=--raw
  [ -n "$cmd" ] || exit 0
  local lc="${cmd,,}"
  case "$lc" in *git*|*gh*) ;; *) exit 0 ;; esac   # cheap pre-filter: nothing else can match
  _sdlc_json_get tool_name
  [ "${REPLY,,}" = powershell ] && segopt="--raw --ps"

  _sdlc_json_get cwd; _sdlc_posix "$REPLY"; cur="$REPLY"
  _sdlc_json_get agent_id
  SUB="$REPLY"   # non-empty = subagent

  local segs="$(sdlc_segments $segopt "$cmd")"
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    sdlc_words "$seg"
    wbase "${SDLC_W[0]}"; base="$REPLY"
    case "$base" in
      cd|pushd|chdir|set-location|sl)
        for ((i = 1; i < ${#SDLC_W[@]}; i++)); do
          case "${SDLC_WR[$i]}" in
            -|~|\$*) break ;;
            -*) ;;
            *) _sdlc_resolve "$cur" "${SDLC_W[$i]}"; cur="$REPLY"; break ;;
          esac
        done ;;
      git) handle_git "$seg" ;;
      gh) handle_gh "$seg" ;;
      echo|printf|grep|egrep|rg|man|which|type|where|whereis|write-host|write-output) ;;
      *)
        # Fail closed: a runner in front of git/gh (xargs, timeout, find -exec, eval, cmd /c, ...) still counts.
        for ((i = 1; i < ${#SDLC_W[@]}; i++)); do
          wbase "${SDLC_W[$i]}"
          if [ "$REPLY" = git ] || [ "$REPLY" = gh ]; then
            base="$REPLY"; rest="${SDLC_WR[*]:$i}"
            if [ "$base" = git ]; then handle_git "$rest"; else handle_gh "$rest"; fi
            break
          fi
        done ;;
    esac
  done <<< "$segs"
}

# Run unless sourced (the tests source this file and call guard_git_main in-process).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  guard_git_main
  exit 0
fi
