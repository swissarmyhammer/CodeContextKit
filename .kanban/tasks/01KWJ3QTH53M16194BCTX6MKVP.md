---
depends_on:
- 01KWJ3PHMFNTH5CV7NAPYM21SJ
position_column: todo
position_ordinal: '8580'
title: 'Walker/reconciler: gitignore-aware walk, hashing, startup cleanup'
---
## What
Create `Sources/CodeContextKit/Index/Walker.swift` + `Reconciler.swift` — port of `crates/swissarmyhammer-code-context/src/cleanup.rs::startup_cleanup`. Walk `rootDirectory` honoring `.gitignore` semantics (replicate `ignore::WalkBuilder`: nested gitignores, skip hidden, skip `.code-context/`), filter to extensions known to `Languages.all`. Concurrent SHA-256 via TaskGroup, store first 16 bytes as content hash. Reconcile against `indexed_files`: deleted → DELETE (cascades), changed hash → mark all layers dirty, new → INSERT dirty. Return `CleanupStats` (walked, added, changed, removed).

## Acceptance Criteria
- [ ] Files matched by `.gitignore` (root and nested) are never indexed; `.code-context/` is skipped
- [ ] Re-running reconcile on an unchanged tree is a no-op (stats all zero deltas)
- [ ] Editing a file's content flips its dirty flags; deleting it removes the row and cascades

## Tests
- [ ] `Tests/CodeContextKitTests/ReconcilerTests.swift` against fixture mini-repos built in temp dirs: gitignore honored (incl. nested), no-op second pass, change/delete/add flows, stats correctness
- [ ] Run `swift test --filter ReconcilerTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.