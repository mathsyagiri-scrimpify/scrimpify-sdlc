#!/usr/bin/env bash
# Minimal test harness. Source this file; call finish at the end.
PASSES=0
FAILS=0

pass() { PASSES=$((PASSES + 1)); echo "  ok   - $1"; }
fail() { FAILS=$((FAILS + 1)); echo "  FAIL - $1"; }

expect_eq() { # actual expected msg
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

expect_contains() { # haystack needle msg
  case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing '$2' in '$1')" ;; esac
}

refute_contains() { # haystack needle msg; an empty haystack is a failure (guards vacuous passes)
  if [ -z "$1" ]; then fail "$3 (haystack is empty; nothing was checked)"; return; fi
  case "$1" in *"$2"*) fail "$3 (found '$2')" ;; *) pass "$3" ;; esac
}

expect_empty() { # value msg
  if [ -z "$1" ]; then pass "$2"; else fail "$2 (expected empty, got '$1')"; fi
}

# pyjson <python-code> [args...]: run a python snippet (python3, else python) for JSON checks.
# Usage: pyjson 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' file.json
# Fails loudly (message on stderr, non-zero) if no interpreter exists; never returns empty silently.
# Tests only; plugin code must not use python.
pyjson() {
  local py
  py="$(command -v python3 || command -v python)" || { echo "pyjson: neither python3 nor python found" >&2; return 127; }
  "$py" -c "$@"
}

finish() {
  echo "  -- $PASSES passed, $FAILS failed"
  if [ "$FAILS" -gt 0 ] || [ "$PASSES" -eq 0 ]; then exit 1; fi
  exit 0
}
