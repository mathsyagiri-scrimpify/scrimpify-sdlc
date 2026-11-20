#!/usr/bin/env bash
# Fixture builders. Source this file from tests.

make_repo() { # dir branch
  local dir="$1" branch="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  echo "# fixture" > "$dir/README.md"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "init"
}

make_cowos_like() { # dir
  local dir="$1"
  make_repo "$dir" main
  mkdir -p "$dir/docs/features/f00-foundation" "$dir/docs/features/f03-inventory" \
    "$dir/docs/features/f05-booking" "$dir/docs/sdlc" "$dir/docs/work/2026/41-product-pricing"
  cat > "$dir/docs/features/f00-foundation/requirements.md" <<'X'
---
id: F00
name: foundation
owner: dev-zero
status: complete
depends_on: []
contracts: []
owns:
  - src/Cowos.Api/Registrations/
---
# Foundation
X
  cat > "$dir/docs/features/f03-inventory/requirements.md" <<'X'
---
id: F03
name: inventory
owner: dev-three
status: active
depends_on: [F00]
contracts: [inventory-catalog]
owns:
  - src/Modules/Inventory/Features/Products/
---
# Inventory
X
  cat > "$dir/docs/features/f05-booking/requirements.md" <<'X'
---
id: F05
name: booking
owner: dev-five
status: active
depends_on: [F00]
contracts: []
owns:
  - src/Modules/Booking/Features/Checkout/
---
# Booking
X
  cat > "$dir/docs/sdlc/paths.txt" <<'X'
# path classes
add-only  src/Cowos.Api/Registrations/
guarded   docs/contracts/
generated web/packages/api-client/
X
  cat > "$dir/docs/work/2026/41-product-pricing/plan.md" <<'X'
Issue: acme/cowos#41
Feature: F03
Task: T002
Branch: 41-product-pricing

## Tests
| Criterion | Test | Layer | File |
|---|---|---|---|
X
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "fixture: cowos-like"
}
