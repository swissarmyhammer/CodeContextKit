---
depends_on:
- 01KWJ3Y9NXM20QGSE7V8WNM2S1
- 01KWJ3XVJ26Y8ER4K87A2PBWVZ
- 01KWJ3TTP3WS2CVQN24XNM05XA
- 01KWJ3WD6MBEDH6WBTH7389ZQG
- 01KWJ3WWABKCYW66S4CZY1Y6JE
- 01KWJ3SEX17Y06SV6D9H0W0XM8
position_column: todo
position_ordinal: 9a80
title: 'CodeContext facade: start/stop lifecycle and end-to-end integration'
---
## What
Create `Sources/CodeContextKit/CodeContext.swift` — the public facade actor tying everything together per plan.md "Goal". `init(rootDirectory:embedder:)` (path enters exactly once; creates the store, `nonisolated let state: CodeContextState`). `start()`: reconcile → project detection → supervisor start → spawn tree-sitter + LSP workers + watcher as owned structured-concurrency tasks, all publishing into `state`. `stop()`: cancel workers, supervisor shutdown, close store. Expose every op as a public async method (indexed, live, diagnostics, `rebuildIndex(layer:)`, `indexStatus()`/`lspStatus()` snapshots reading `state`, and `detectProjects()` which **re-scans and refreshes `state.projects`**). Fake-backed only — the gated live sourcekit-lsp smoke is a separate follow-on task.

## Acceptance Criteria
- [ ] End-to-end on a fixture repo with FakeEmbedder + fake connections: start → isReady; searchSymbol/searchCode/callGraph/diagnostics all answer; stop() leaves no running tasks or open DB handles
- [ ] `detectProjects()` after adding a new marker file to the fixture re-scans and `state.projects` reflects the addition
- [ ] `rebuildIndex(.treeSitter)` through the facade re-drains and `indexStatus()` counts reflect it
- [ ] Two CodeContexts on two temp workspaces run concurrently without interference

## Tests
- [ ] `Tests/CodeContextKitTests/CodeContextE2ETests.swift`: full-lifecycle fixture test, detectProjects re-scan, rebuild/status round-trip, dual-workspace isolation, stop-idempotency
- [ ] Run `swift test --filter CodeContextE2ETests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.