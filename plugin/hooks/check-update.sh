#!/usr/bin/env bash
# Update check: prints one line when a newer release tag exists, nothing when current,
# or an "update check failed" line. Never prompts and never hangs.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CUR="$(tr -d '\r\n' < "$ROOT/VERSION" 2>/dev/null)"
REMOTE="${SCRIMPIFY_SDLC_REMOTE:-https://github.com/mathsyagiri-scrimpify/scrimpify-sdlc.git}"
export GIT_TERMINAL_PROMPT=0

fail() { echo "scrimpify-sdlc update check failed: $1"; exit 0; }

[ -n "$CUR" ] || fail "installed version unknown"
T=""; command -v timeout >/dev/null 2>&1 && T="timeout 20"
err="$(mktemp 2>/dev/null)" || fail "no temp file"
trap 'rm -f "$err"' EXIT
if ! tags="$($T git ls-remote --tags "$REMOTE" 2>"$err" </dev/null)"; then
  reason="$(head -n 1 "$err" | tr -d '\r')"
  fail "${reason:-could not reach $REMOTE}"
fi
latest="$(printf '%s\n' "$tags" | sed -n -E 's#^.*refs/tags/v([0-9]+\.[0-9]+\.[0-9]+)$#\1#p' | sort -V | tail -n 1)"
[ -n "$latest" ] || exit 0
[ "$latest" != "$CUR" ] || exit 0
top="$(printf '%s\n%s\n' "$CUR" "$latest" | sort -V | tail -n 1)"
[ "$top" = "$latest" ] || exit 0
echo "scrimpify-sdlc v$latest is available (installed v$CUR): run claude plugin update scrimpify-sdlc@scrimpify-sdlc"
exit 0
