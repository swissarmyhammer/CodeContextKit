---
depends_on:
- 01KWJ3P3GAY5KVH271AZNAS8D1
position_column: todo
position_ordinal: '8280'
title: LanguageModule protocol, core types, and first modules (swift/rust/python)
---
## What
Create `Sources/CodeContextKit/Languages/LanguageModule.swift`: the strategy protocol per plan.md — `name`, `fileExtensions`, `treeSitterLanguage: Language?`, `chunkKinds: [String: SymbolMetaType]`, `containerNodeKinds: Set<String>`, `projectMarkers: [ProjectMarker]`, `languageServer: ServerSpec?`. Supporting value types in the same directory: `SymbolMetaType` (function|method|type|other), `ProjectMarker` (fileName or glob), `ServerSpec` (command, args, languageIds, startupTimeout 30s default, healthCheckInterval 60s default, installHint). `Languages.all` registry enum. First three modules as separate files — `Swift.swift`, `Rust.swift`, `Python.swift` — with chunk-kind tables ported from the Rust `EMBEDDABLE_NODE_KINDS`/`CONTAINER_KINDS` in `crates/swissarmyhammer-treesitter/src/chunk.rs`, markers from `swissarmyhammer-project-detection`, server specs from `builtin/lsp/{sourcekit-lsp,rust-analyzer,pylsp}.yaml`.

## Acceptance Criteria
- [ ] `Languages.all` contains the three modules; extension→module lookup helper resolves `.swift`, `.rs`, `.py`
- [ ] Each module's `chunkKinds` maps at least function-like and type-like node kinds to correct meta-types
- [ ] `ServerSpec` defaults match plan (30s startup, 60s health)

## Tests
- [ ] `Tests/CodeContextKitTests/LanguageModuleTests.swift`: registry lookup by extension; chunkKinds meta-type spot checks per module (e.g. rust `function_item` → .function, `struct_item` → .type); ServerSpec defaults
- [ ] Run `swift test --filter LanguageModuleTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.