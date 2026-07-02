---
depends_on:
- 01KWJ3YW2ZK0J862WBYDY8WF8X
position_column: todo
position_ordinal: 9c80
title: Gated live sourcekit-lsp integration smoke (crash/restart)
---
## What
Create `Tests/CodeContextKitTests/LiveSourceKitTests.swift` — the real-server end-to-end smoke from plan.md testing strategy, gated on env `CCK_LIVE_LSP=1` (suite skips otherwise, so CI without the gate stays green). Against a temp swift fixture package using the real `sourcekit-lsp` from the active toolchain: `CodeContext.start()` → await `state.isReady` server-settled → `definition` on a known symbol returns `.liveLSP` → read the daemon pid from `state.servers` and `kill -9` it → assert the supervisor auto-restarts (state transitions failed → running, restart counter incremented) → a post-restart `definition` succeeds again. Generous timeouts; skip (not fail) with a clear message if `sourcekit-lsp` is not on PATH even when gated in.

## Acceptance Criteria
- [ ] Without `CCK_LIVE_LSP=1`, the suite reports skipped, exit 0
- [ ] With the gate on a machine with Xcode: spawn → index → live definition → kill -9 → auto-restart → live definition all pass in one run
- [ ] Restart evidence asserted from `state.servers` (attempts incremented, state running), not from log scraping

## Tests
- [ ] `swift test --filter LiveSourceKitTests` → skipped by default; `CCK_LIVE_LSP=1 swift test --filter LiveSourceKitTests` → passes on a dev machine
- [ ] Run `swift test` (ungated) → whole suite green with the live tests skipped

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.