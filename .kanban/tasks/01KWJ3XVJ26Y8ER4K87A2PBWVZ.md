---
depends_on:
- 01KWJ3S972X06D1TKBDBCVB3SD
- 01KWJ3VNKRFPHF36XXH740CWZM
position_column: todo
position_ordinal: '9880'
title: 'Diagnostics op: settle engine, scopes, dependents fold-in'
---
## What
Create `Sources/CodeContextKit/Diagnostics/` — port of `crates/swissarmyhammer-diagnostics/{diagnose,settle,record}.rs`. `diagnostics(scope:severity:)` with `.workingTree` (git status: modified+untracked+staged), `.file(glob)`, `.sha(range)` scopes and a **severity floor parameter defaulting to `.warning`** (records below the floor excluded; lowering to `.hint` includes everything); paths absolutized, confined to root, filtered to diagnosable extensions. For each target: syncOpen + pullDiagnostics, then the settle engine — subscribe to the session diagnostics stream, seed from cache, `Settled` after 300ms quiescence, `Pending` at 5s hard timeout (injectable clock). Dependents: one-hop inbound via blastRadius; only **broken** dependents (≥1 error/warning) fold in, ranked errors-then-warnings, capped at 100 per report. `pending: true` when settle timed out or session `!isReady`. `DiagnosticsReport { records, counts, pending }`.

## Acceptance Criteria
- [ ] Manual-clock settle: an update at t+200ms restarts the quiescence window; silence to t+300ms → Settled; continuous updates → Pending at 5s
- [ ] Severity floor: hint/info diagnostics excluded at the default `.warning` floor, included when the floor is lowered to `.hint`
- [ ] Clean dependents are excluded; broken dependents appear ranked after queried files
- [ ] Server running but not ready → report flagged pending even if empty

## Tests
- [ ] `Tests/CodeContextKitTests/DiagnosticsTests.swift`: settle timing matrix with manual clock; severity floor filtering; scope resolution against a temp git repo fixture; dependents fold-in with seeded call edges; pending flag truth table
- [ ] Run `swift test --filter DiagnosticsTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.