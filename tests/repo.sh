#!/usr/bin/env bash
# Repo manifests and harness self-test.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib.sh"

# manifests agree on version
ver="$(tr -d '[:space:]' < "$ROOT/plugin/VERSION")"
pj="$(python -c "import json,sys;print(json.load(open(sys.argv[1]))['version'])" "$ROOT/plugin/.claude-plugin/plugin.json")"
expect_eq "$pj" "$ver" "plugin.json version equals VERSION"
expect_eq "$ver" "0.1.0" "version is 0.1.0"

# marketplace
mk="$ROOT/.claude-plugin/marketplace.json"
count="$(python -c "import json,sys;print(len(json.load(open(sys.argv[1]))['plugins']))" "$mk")"
name="$(python -c "import json,sys;print(json.load(open(sys.argv[1]))['plugins'][0]['name'])" "$mk")"
src="$(python -c "import json,sys;print(json.load(open(sys.argv[1]))['plugins'][0]['source'])" "$mk")"
expect_eq "$count" "1" "marketplace has one plugin"
expect_eq "$name" "scrimpify-sdlc" "marketplace plugin name"
expect_eq "$src" "./plugin" "marketplace plugin source"

# harness self-test: refute_contains on an empty haystack must count as a failure
[ "$(bash -c 'source "$1/tests/lib.sh"; refute_contains "" x e >/dev/null; finish >/dev/null' _ "$ROOT"; echo $?)" = "1" ] \
  && pass "refute_contains on empty haystack fails" || fail "refute_contains on empty haystack must fail"
[ "$(bash -c 'source "$1/tests/lib.sh"; finish >/dev/null' _ "$ROOT"; echo $?)" = "1" ] \
  && pass "finish fails with zero passes" || fail "finish must fail with zero passes"

finish
