---
depends_on:
- 01KWJ3PSVZTXYZDX1ASZ3GN09M
position_column: todo
position_ordinal: 9b80
title: Tree-sitter-only format modules (sql, json, yaml, markdown, bash)
---
## What
Add the tree-sitter-only format modules, one file each under `Sources/CodeContextKit/Languages/`: SQL, JSON, YAML, Markdown, Bash — all with `languageServer: nil`. Register in `Languages.all`; add their grammar SPM dependencies to `Package.swift` (note any needing wrapper packages in doc comments, same convention as the LSP-backed module task). Chunk-kind tables from Rust `chunk.rs` (e.g. SQL `create_*` statements → .type/.function analogues per the Rust mapping, markdown sections, bash function definitions).

## Acceptance Criteria
- [ ] Extension lookup resolves .sql/.json/.yaml/.yml/.md/.sh
- [ ] Every format module has `languageServer == nil` and non-empty `chunkKinds`
- [ ] Each grammar parses a fixture snippet with a non-error root node

## Tests
- [ ] Extend `Tests/CodeContextKitTests/LanguageModuleTests.swift`: chunkKinds spot checks per format (e.g. bash `function_definition` → .function), nil-server assertions, parse smoke tests
- [ ] Run `swift test --filter LanguageModuleTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.