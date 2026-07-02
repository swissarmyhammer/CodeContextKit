---
depends_on:
- 01KWJ3VY63EM20R393B7REJSFY
- 01KWJ3PHMFNTH5CV7NAPYM21SJ
position_column: todo
position_ordinal: '9580'
title: 'LSP indexer worker: documentSymbol + call hierarchy into the store'
---
## What
Create `Sources/CodeContextKit/Index/LspIndexWorker.swift` — port of `lsp_worker.rs` + `lsp_communication.rs` + `lsp_indexer.rs` + `invalidation.rs`. One worker task per running daemon, draining `lsp_indexed = 0` files matching that server's extensions in batches: syncOpen → documentSymbols (flatten nested symbols to `FlatSymbol` with qualified path + stable symbol id) → prepareCallHierarchy/outgoingCalls per function/method/constructor symbol → didClose → persist `lsp_symbols` + `lsp_call_edges(source='lsp')` → mark indexed. Invalidation rule: when a re-indexed file's symbol set shrinks, files holding edges into removed symbol ids get `lsp_indexed = 0`. Idle backoff (500ms idle, 5s when session unavailable, injectable clock).

## Acceptance Criteria
- [ ] Fixture drain via FakeLanguageServerConnection persists flattened symbols with qualified paths and lsp-source edges
- [ ] Shrinking a file's scripted symbol set marks dependent files lsp-dirty (invalidation)
- [ ] Worker survives a connection error mid-batch: file stays dirty, no partial rows committed

## Tests
- [ ] `Tests/CodeContextKitTests/LspIndexWorkerTests.swift` with scripted fake connection: drain goldens, invalidation propagation, mid-batch failure atomicity, idle backoff via manual clock
- [ ] Run `swift test --filter LspIndexWorkerTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.