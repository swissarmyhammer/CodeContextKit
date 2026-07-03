---
comments:
- actor: wballard
  id: 01kwn45n7sg1h3mm34fy7p72pb
  text: |-
    Implemented. Sources/CodeContextKit/Ops/LayeredContext.swift (SourceLayer enum, LayeredSymbolInfo, LayeredChunkInfo, lsp_symbols/lsp_call_edges/ts_chunks query helpers, enrichLocation) + Sources/CodeContextKit/Ops/LiveOpsCore.swift (5 ops: definition, typeDefinition, hover, references, implementations, each cascading live session -> lsp index -> tree-sitter -> none). Also added 5 typed wrapper methods to LspSession.swift (definition/typeDefinition/hover/references/implementations) delegating to LanguageServerConnection, and 5 setter methods to Tests/.../Support/FakeLanguageServerConnection.swift mirroring the existing setDocumentSymbolsResult pattern.

    Deliberate divergences from the Rust reference (documented in LiveOpsCore's type doc comment):
    1. Both follower-router seams (LiveLspRouter/MultiLspRouter) removed per task instructions -- this Swift port has no cross-process leader/follower topology.
    2. All 5 ops cascade through all 4 layers uniformly, including typeDefinition and implementations -- the Rust reference restricts typeDefinition to live-LSP-only and skips the LSP-index layer for implementations. This port's schema draws no such distinction, and the task's acceptance criteria explicitly calls for a uniform "4 layers x 5 ops" test matrix.

    Tests/CodeContextKitTests/LayeredOpsTests.swift: 25 tests covering the full 4x5 cascade matrix, fall-through on induced live-LSP connection errors (definition->lspIndex, hover->treeSitter, references->none), and syncOpen-before-live-request ordering (verified via FakeLanguageServerConnection.calls index comparison + didOpen text content).

    swift test --filter LayeredOpsTests: 25/25 pass. Full swift test: 390/390 pass, zero warnings.
  timestamp: 2026-07-03T23:14:10.809261+00:00
- actor: wballard
  id: 01kwn4jkwcjzm5bmnvbkvmzzen
  text: |-
    really-done verification complete. Fresh `swift test --filter LayeredOpsTests`: 25/25 pass. Fresh `swift test` (full suite, 3 consecutive runs): 390/390 pass, zero warnings (one isolated flake in the pre-existing ConnectionTests suite on an unrelated run, matching that suite's own documented process-contention flakiness under load -- not part of this diff, not reproduced on 3 subsequent runs).

    Adversarial double-check verdict: PASS. Verified SQL column bindings against Migrations.swift, the from_ranges JSON round-trip between LSPIndexWorker.encodeFromRanges/TSCallGraph.writeEdge (writers) and LayeredContext.parseFromRanges (reader), the syncOpen-before-live-request and error-swallowing-falls-through contracts, and that the 25 tests assert substantively (not vacuously). Two minor non-blocking observations noted (a slightly loose `>= 1` assertion in one test, and one redundant-but-harmless extra query in indexedImplementations' tree-sitter fallback) -- neither warrants a revision.

    Task left in doing column per /implement workflow, ready for /review.
  timestamp: 2026-07-03T23:21:15.404264+00:00
depends_on:
- 01KWJ3WNDEXN2N4BSACPC5H3J4
- 01KWJ3TB95F2J0CZYW17DCP9H8
position_column: doing
position_ordinal: '80'
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