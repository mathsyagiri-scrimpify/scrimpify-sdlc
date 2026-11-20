#!/usr/bin/env bash
# SessionStart hook: announce the plugin and load STANDARD.md into the session context.
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION" 2>/dev/null)"
[ -n "$VERSION" ] || exit 0
[ -f "$ROOT/STANDARD.md" ] || exit 0
ctx="$(printf 'scrimpify-sdlc v%s is active in this repo. Plugin files: %s.\n\n%s' "$VERSION" "$ROOT" "$(cat "$ROOT/STANDARD.md")" | sdlc_json_escape)"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
exit 0
