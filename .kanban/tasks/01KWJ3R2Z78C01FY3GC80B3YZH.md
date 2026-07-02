---
depends_on:
- 01KWJ3PSVZTXYZDX1ASZ3GN09M
position_column: todo
position_ordinal: '8680'
title: LSP-backed v1 language modules (ts/tsx/js, go, c/cpp, java, c#, php)
---
## What
Add the LSP-backed remainder of the v1 set, one file per module under `Sources/CodeContextKit/Languages/`: TypeScript, TSX, JavaScript (shared `typescript-language-server` ServerSpec instance), Go (`gopls`), C and C++ (shared `clangd` spec), Java (`jdtls`), CSharp (`omnisharp`), PHP (`intelephense`). Register in `Languages.all`. Add grammar SPM dependencies to `Package.swift`. **Grammar availability spike (explicit AC below): enumerate which of these grammars ship upstream Package.swift support and which need a wrapper package; record the findings as a table in the module files' doc comments, and create wrapper repos under the swissarmyhammer org only for the ones that need it.** Chunk-kind tables ported per language from Rust `chunk.rs`; markers from `swissarmyhammer-project-detection`; specs from `builtin/lsp/*.yaml`.

## Acceptance Criteria
- [ ] Extension lookup resolves .ts/.tsx/.js/.go/.c/.cpp/.java/.cs/.php
- [ ] js/ts/tsx modules reference the identical ServerSpec instance (dedupe-by-command yields one command); likewise c/cpp
- [ ] Grammar availability table documented; every grammar dependency resolves and parses a snippet (non-error root node)

## Tests
- [ ] Extend `Tests/CodeContextKitTests/LanguageModuleTests.swift`: per-module chunkKinds spot checks (e.g. java `method_declaration` → .method, c# `class_declaration` → .type); shared-spec identity assertions; parse smoke test per grammar
- [ ] Run `swift test --filter LanguageModuleTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.