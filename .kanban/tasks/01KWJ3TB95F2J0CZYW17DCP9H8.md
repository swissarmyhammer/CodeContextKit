---
depends_on:
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: todo
position_ordinal: '8e80'
title: 'Indexed symbol ops: getSymbol, searchSymbol, listSymbols, grepCode'
---
## What
Create `Sources/CodeContextKit/Ops/SymbolOps.swift` + `GrepCode.swift` + `IndexAdmin.swift` — ports of `ops/get_symbol.rs`, `ops/search_symbol.rs`, `ops/list_symbols.rs`, `ops/grep_code.rs`, plus the index admin ops (`ops/get_status.rs`, `ops/rebuild_index.rs`). `getSymbol(query:maxResults:)` with match tiers Exact > Suffix > CaseInsensitive > Fuzzy over `symbol_path` (and `lsp_symbols` when present), tier + score in results. `searchSymbol(query:kind:maxResults:)` fuzzy with optional meta-type filter. `listSymbols(file:)`. `grepCode(pattern:languages:filePattern:maxResults:)` — regex over `ts_chunks.text` concurrently (TaskGroup), returning matches with positions. `indexStatus()` — counts per layer (files, ts-indexed, lsp-indexed, embedded %) from `indexed_files`. `rebuildIndex(layer:)` — mark all files dirty for the given layer (.treeSitter, .lsp, .embedding, .all) so workers re-drain. All results `Codable & Sendable` value types.

## Acceptance Criteria
- [ ] Exact `symbol_path` match outranks suffix which outranks fuzzy for the same query
- [ ] grepCode respects language and file-pattern filters and the max-results cap
- [ ] listSymbols on an indexed fixture file returns its chunk symbols in file order
- [ ] `rebuildIndex(.treeSitter)` marks all files ts-dirty and a worker drain re-populates chunks; `indexStatus()` counts reflect before/after

## Tests
- [ ] `Tests/CodeContextKitTests/SymbolOpsTests.swift`: tier ordering, kind filter, listSymbols golden, grep filters/caps — against a store populated by the chunker on fixtures; `IndexAdminTests.swift`: rebuild → re-drain cycle, status count correctness
- [ ] Run `swift test --filter SymbolOpsTests` and `--filter IndexAdminTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.