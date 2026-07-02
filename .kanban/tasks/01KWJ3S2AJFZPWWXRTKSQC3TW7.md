---
depends_on:
- 01KWJ3QTH53M16194BCTX6MKVP
- 01KWJ3PSVZTXYZDX1ASZ3GN09M
position_column: todo
position_ordinal: '8980'
title: Generic chunker and tree-sitter indexing worker
---
## What
Create `Sources/CodeContextKit/TreeSitter/Chunker.swift` + `Sources/CodeContextKit/Index/TreeSitterWorker.swift` — port of `crates/swissarmyhammer-treesitter/src/chunk.rs` made generic over `Languages.all`. `Chunker.chunk(file:module:) -> [SemanticChunk]`: recurse the AST, emit a chunk per node whose kind is in the module's `chunkKinds` (stamped with its `SymbolMetaType`), build qualified `symbol_path` (e.g. `Struct::method`) from `containerNodeKinds` + name-field heuristics (name/identifier/declarator fields). Worker: drain `ts_indexed = 0` from the store, parse, chunk, write `ts_chunks` rows (embedding NULL for now), mark `ts_indexed = 1`. Parsing outside DB transactions.

## Acceptance Criteria
- [ ] Swift fixture: methods inside a struct chunk with `Struct.method` symbol_path and `.method` kind; free functions get `.function`
- [ ] Rust fixture: `impl_item` container qualification matches the Rust implementation's output
- [ ] Worker drains dirty files idempotently; re-run with no dirty files writes nothing

## Tests
- [ ] `Tests/CodeContextKitTests/ChunkerTests.swift`: golden chunk sets (path, kind, ranges) for swift/rust/python fixture sources; `TreeSitterWorkerTests.swift`: drain cycle against an in-memory store
- [ ] Run `swift test --filter ChunkerTests` and `--filter TreeSitterWorkerTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.