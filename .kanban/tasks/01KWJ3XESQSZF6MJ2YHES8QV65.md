---
depends_on:
- 01KWJ3WNDEXN2N4BSACPC5H3J4
- 01KWJ3TB95F2J0CZYW17DCP9H8
position_column: todo
position_ordinal: '9780'
title: Layered cascade and core live ops (definition/typeDefinition/hover/references/implementations)
---
## What
Create `Sources/CodeContextKit/Ops/LayeredContext.swift` + `LiveOpsCore.swift` — port of `layered_context.rs` with both follower router seams removed. Cascade per op: (1) live session (`syncOpen` current disk text + typed request) tagged `.liveLSP`; (2) persisted `lsp_symbols`/`lsp_call_edges` tagged `.lspIndex`; (3) tree-sitter chunks tagged `.treeSitter`; (4) empty result tagged `.none` — never an error for "no data". Implement the five core live ops: `definition`, `typeDefinition`, `hover`, `references`, `implementations`, each returning a `Codable & Sendable` result carrying `sourceLayer`.

## Acceptance Criteria
- [ ] With a live fake session, ops return `.liveLSP` results; with session nil but index populated, `.lspIndex`; index empty but chunks present, `.treeSitter`; all empty, `.none` with empty payload
- [ ] Live-layer errors (connection failure) fall through to the next layer rather than surfacing
- [ ] `syncOpen` is called with current disk content before every live request

## Tests
- [ ] `Tests/CodeContextKitTests/LayeredOpsTests.swift`: cascade matrix (4 layers × 5 ops) using fake session + seeded store; fall-through on induced live error; syncOpen ordering assertion
- [ ] Run `swift test --filter LayeredOpsTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.