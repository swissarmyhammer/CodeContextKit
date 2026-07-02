---
depends_on:
- 01KWJ3PSVZTXYZDX1ASZ3GN09M
- 01KWJ3QTH53M16194BCTX6MKVP
position_column: todo
position_ordinal: '8880'
title: Project detection from LanguageModule markers
---
## What
Create `Sources/CodeContextKit/Projects/ProjectDetection.swift` — port of `crates/swissarmyhammer-project-detection` driven by `Languages.all` markers instead of a hardcoded table. **Reuse the `Walker` from the walker/reconciler task for gitignore-aware traversal — do not re-implement gitignore semantics.** Match each module's `projectMarkers` (exact names like `Cargo.toml` and globs like `*.csproj`); one directory can match multiple modules; a monorepo yields one `DetectedProject(language, directory)` per hit. Public `Codable & Sendable` result type. Helper `serverSpecs(for: [DetectedProject]) -> [ServerSpec]` returning specs deduped by command.

## Acceptance Criteria
- [ ] A fixture monorepo with Package.swift + Cargo.toml + two package.json dirs detects swift, rust, and javascript/typescript projects with correct directories
- [ ] Dedupe: two package.json hits yield exactly one `typescript-language-server` spec
- [ ] Gitignored subtrees (e.g. node_modules via .gitignore) produce no detections — via the shared Walker, not a local reimplementation

## Tests
- [ ] `Tests/CodeContextKitTests/ProjectDetectionTests.swift` against temp-dir fixture repos: polyglot detection, multi-type single dir, dedupe-by-command, gitignore exclusion
- [ ] Run `swift test --filter ProjectDetectionTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.