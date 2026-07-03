---
comments:
- actor: wballard
  id: 01kwkaz6ksnvszy1mg9fq43n9m
  text: |-
    Implemented via TDD. Created:
    - Sources/CodeContextKit/Ops/SymbolOps.swift — getSymbol (4-tier: exact/suffix/caseInsensitive/fuzzy), searchSymbol (fuzzy + meta-type filter), listSymbols. One shared loadCandidateRows() merges ts_chunks + lsp_symbols by (file_path, start_line), used by all three ops (avoids the 3x duplication the Rust reference has). Fuzzy matching is a hand-rolled subsequence scorer (word-boundary + contiguous-run bonuses) since there's no skim-equivalent Swift dependency.
    - Sources/CodeContextKit/Ops/GrepCode.swift — regex over ts_chunks.text via TaskGroup, language + glob (fnmatch) file-pattern filters, maxResults cap + truncated flag.
    - Sources/CodeContextKit/Ops/IndexAdmin.swift — indexStatus() (per-layer counts/percentages from indexed_files) and rebuildIndex(layer:) (.treeSitter/.lsp/.embedding/.all).

    Supporting changes: added Store.markAllDirty(layer:) (bulk per-layer dirty reset, reusing IndexLayer's column mapping rather than duplicating it); added CodeContextError.pattern for grep regex compile failures; loosened Chunker.symbolPathSeparator from private to internal so SymbolOps reuses the same "." separator instead of duplicating it.

    Deviations from the Rust reference (documented in SymbolOps.swift's type doc comment):
    - Swift's lsp_symbols schema has no id-encoded qualified path (autoincrement Int id vs Rust's "source:file:qpath" string), so a merged candidate always keeps its qualified path from ts_chunks; only name/kind/detail/columns are LSP-enriched. An LSP-only candidate falls back to its bare name.
    - ts_chunks.kind is a Swift-only schema addition, so tree-sitter-only candidates always have a known SymbolMetaType (Rust's TS-only rows have none).
    - grepCode's filePattern is a single glob (POSIX fnmatch) per the task's signature, not Rust's exact-path list.
    - Rust's list_symbol.rs -> ported as listSymbols within SymbolOps.swift (file is literally named list_symbol.rs, singular, not list_symbols.rs as the task description said).
    - rebuildIndex only flips dirty bits; it doesn't drive a worker drain itself (matches Rust's own documented contract).

    Ran `mcp__sah__review` on the working diff: found 2 legitimate gaps (case-insensitivity of the LSP kind-name map and the fuzzy scorer were only exercised with lowercase-only fixtures) — added getSymbolFuzzyQueryIsCaseInsensitive and getSymbolLspKindNameMappingIsCaseInsensitive to close them. The review also flagged pre-existing Store.read/write duplication (Store.swift lines ~81/92) — left alone as out of scope/pre-existing, not introduced by this task.

    Full `swift test`: 241/241 passing, 18 suites, zero warnings from new code. `swift test --filter SymbolOpsTests` (22 tests) and `--filter IndexAdminTests` (5 tests) both green.
  timestamp: 2026-07-03T06:34:30.393642+00:00
- actor: wballard
  id: 01kwkb6stwfjppmpj474ewnx31
  text: |-
    Adversarial double-check (subagent) verdict: PASS, no blocking findings. It independently re-ran swift build/swift test (241/241 green at that point), verified the TaskGroup regex-recompilation fix is genuinely necessary and correct under Swift 6 strict concurrency, checked the suffix-tier pattern-building for false-positive risk (none — hasSuffix requires the literal "." separator), verified rebuildIndex(.all) counting is correct (no triple-count), and confirmed no force-unwraps/single-letter names/missing docs in the three new Ops files. It flagged one advisory gap (grep byte-offset positions untested with multi-byte UTF-8 content) — closed by adding grepCodeMatchPositionsAreUTF8ByteOffsetsNotCharacterOffsets (uses "café" to prove true UTF-8 byte offsets, not character offsets).

    Final state: swift build clean (0 warnings from new/touched files), swift test 242/242 passing across 18 suites. Leaving task in doing for /review.
  timestamp: 2026-07-03T06:38:39.452159+00:00
depends_on:
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: doing
position_ordinal: '80'
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