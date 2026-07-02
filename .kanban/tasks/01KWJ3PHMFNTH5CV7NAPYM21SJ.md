---
depends_on:
- 01KWJ3P3GAY5KVH271AZNAS8D1
position_column: todo
position_ordinal: '8180'
title: 'SQLite store: GRDB schema, migrations, dirty flags, embedding codec'
---
## What
Create `Sources/CodeContextKit/Index/Store.swift` (+ `Migrations.swift`, `EmbeddingCodec.swift`). GRDB `DatabasePool` opened at `<root>/.code-context/kit.db`, WAL mode, directory bootstrap with self-`.gitignore` (`*`). Schema per plan.md: `indexed_files` (file_path PK, content_hash BLOB, file_size, last_seen_at, ts_indexed/lsp_indexed/embedded flags), `ts_chunks` (file_path FK CASCADE, byte/line ranges, text, symbol_path, kind meta-type TEXT, embedding BLOB nullable), `lsp_symbols`, `lsp_call_edges` (source 'lsp'|'treesitter'), `meta` (embedder dimension). Dirty-flag helpers (markDirty, drainTsDirty, drainLspDirty, markIndexed). `EmbeddingCodec`: [Float] ⇄ little-endian Data round-trip.

## Acceptance Criteria
- [ ] Opening a store on a fresh directory creates `.code-context/kit.db` + `.gitignore` and runs all migrations
- [ ] Foreign-key cascade: deleting an `indexed_files` row removes its chunks/symbols/edges
- [ ] Embedding codec round-trips arbitrary [Float] exactly

## Tests
- [ ] `Tests/CodeContextKitTests/StoreTests.swift`: fresh-open creates schema; dirty-flag drain/mark cycle; FK cascade; codec round-trip incl. empty and 1024-dim vectors
- [ ] Run `swift test --filter StoreTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.