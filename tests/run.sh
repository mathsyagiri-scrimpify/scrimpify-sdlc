#!/usr/bin/env bash
# Runs every tests/*.sh (except the helpers) in its own subshell.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0
total=0
for t in "$HERE"/*.sh; do
  base="$(basename "$t")"
  case "$base" in lib.sh|run.sh|fixtures.sh) continue ;; esac
  total=$((total + 1))
  echo "== $base"
  if ! ( bash "$t" ); then failed=$((failed + 1)); fi
done
echo "== $total test files, $failed failed"
[ "$failed" -eq 0 ]
