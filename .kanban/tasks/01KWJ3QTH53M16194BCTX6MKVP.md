---
comments:
- actor: wballard
  id: 01kwjkh5qrrsc6pxcd5225k9r5
  text: |-
    Implemented via TDD (RED confirmed: build failed with "cannot find 'Walker'/'Reconciler' in scope" before implementation existed).

    Files added:
    - Sources/CodeContextKit/Index/Gitignore.swift (internal GitignorePattern/GitignoreStack) — hand-rolled gitignore matcher since Package.swift has no gitignore-parsing dependency. Scoped to what the fixtures need: glob wildcards `*`/`**`/`?`, character classes `[abc]`/`[!abc]`, `!` negation, directory-only trailing `/`, anchored vs. basename-anywhere matching, nested `.gitignore` precedence (root-to-leaf accumulation, last-match-wins). Documented as not a fully spec-complete git matcher in the file's doc comment.
    - Sources/CodeContextKit/Index/Walker.swift (internal Walker enum) — recursive gitignore-aware walk, skips hidden dot-prefixed entries (covers `.git/` and `.code-context/` with no special case) and symlinks, filters to `Languages.all` extensions, concurrent SHA-256 (CryptoKit, first 16 bytes) via TaskGroup. Exposed `walkEntries`/`enumerateFiles(extensions:)` as reusable lower-level primitives beyond just the hash-everything path, since sibling tasks (queryAST ^h0w0xm8, project detection ^ahd6jsk) already state they'll reuse "the shared Walker" for gitignore-aware traversal without re-implementing gitignore semantics.
    - Sources/CodeContextKit/Index/Reconciler.swift (public Reconciler enum + public CleanupStats struct) — reconcile(store:rootDirectory:), reuses Store.markDirty for both new and changed files (single upsert covers both per Store's existing SQL), issues DELETE directly via store.write/Schema constants for removed files (Store.read/write are documented as the walker's escape hatch for this).
    - Tests/CodeContextKitTests/ReconcilerTests.swift — 13 tests: add/no-op/change/delete flows, combined stats, root gitignore, nested gitignore scoping, negation, directory-only pattern, .code-context/ skip, plus direct Walker unit tests for hashing and extension filtering.

    Verification: `swift build` clean (exit 0, no warnings from new files), `swift test` full suite 129/129 passed across 8 suites (no regressions). Adversarial double-check agent reviewed the diff independently (hand-traced gitignore regex compilation for 9 patterns, verified reconcile SQL against Migrations.swift schema, checked Sendable/concurrency safety) — verdict PASS, no findings.

    Deviation noted (in-scope, not a gap): unlike the Rust reference's `startup_cleanup`, this port does not touch `last_seen_at` on unchanged files and does not do the `mark_non_lsp_capable_files` bulk step — neither was in this task's stated scope (deleted→DELETE / changed→markDirty / new→markDirty only). Flagging in case a future task needs `last_seen_at`-based staleness.

    Left in `doing` per /implement workflow — ready for /review.
  timestamp: 2026-07-02T23:44:53.496228+00:00
depends_on:
- 01KWJ3PHMFNTH5CV7NAPYM21SJ
position_column: doing
position_ordinal: '80'
title: 'Walker/reconciler: gitignore-aware walk, hashing, startup cleanup'
---
## What
Create `Sources/CodeContextKit/Index/Walker.swift` + `Reconciler.swift` — port of `crates/swissarmyhammer-code-context/src/cleanup.rs::startup_cleanup`. Walk `rootDirectory` honoring `.gitignore` semantics (replicate `ignore::WalkBuilder`: nested gitignores, skip hidden, skip `.code-context/`), filter to extensions known to `Languages.all`. Concurrent SHA-256 via TaskGroup, store first 16 bytes as content hash. Reconcile against `indexed_files`: deleted → DELETE (cascades), changed hash → mark all layers dirty, new → INSERT dirty. Return `CleanupStats` (walked, added, changed, removed).

## Acceptance Criteria
- [x] Files matched by `.gitignore` (root and nested) are never indexed; `.code-context/` is skipped
- [x] Re-running reconcile on an unchanged tree is a no-op (stats all zero deltas)
- [x] Editing a file's content flips its dirty flags; deleting it removes the row and cascades

## Tests
- [x] `Tests/CodeContextKitTests/ReconcilerTests.swift` against fixture mini-repos built in temp dirs: gitignore honored (incl. nested), no-op second pass, change/delete/add flows, stats correctness
- [x] Run `swift test --filter ReconcilerTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.