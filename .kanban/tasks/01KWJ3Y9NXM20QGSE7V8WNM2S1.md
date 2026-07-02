---
depends_on:
- 01KWJ3XESQSZF6MJ2YHES8QV65
position_column: todo
position_ordinal: '9980'
title: 'Remaining live ops: codeActions, renameEdits, inboundCalls, workspaceSymbols, lspStatus'
---
## What
Create `Sources/CodeContextKit/Ops/LiveOpsExtended.swift` — the remaining five of the ten v1 live ops on the layered cascade: `codeActions(in:at:)` (codeAction + resolve), `renameEdits(in:at:newName:)` — prepareRename + rename executed **under one connection hold** so no other consumer interleaves (port of `lsp_multi_request_batch` semantics; degrade to `canRename: false` when no live layer), `inboundCalls(of:)` (prepareCallHierarchy + incomingCalls), `workspaceSymbols(query:)` via `anySession()` (document-less), and `lspStatus()` snapshot from the supervisor. All results `Codable & Sendable` with `sourceLayer` where the cascade applies.

## Acceptance Criteria
- [ ] renameEdits issues prepareRename and rename with no interleaved calls on the fake connection (call-order recording proves atomicity)
- [ ] renameEdits with no live session returns `canRename: false` (not an error)
- [ ] workspaceSymbols works with any running session; lspStatus reflects supervisor daemon states

## Tests
- [ ] `Tests/CodeContextKitTests/LiveOpsExtendedTests.swift` with fake session/supervisor: rename atomicity + degradation, codeAction resolve flow, inboundCalls mapping, workspaceSymbols routing, lspStatus snapshot
- [ ] Run `swift test --filter LiveOpsExtendedTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.