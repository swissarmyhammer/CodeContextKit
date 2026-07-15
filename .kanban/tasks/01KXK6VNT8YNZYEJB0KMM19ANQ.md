---
assignees:
- claude-code
depends_on:
- 01KXK6V0R16MGXA4QAD2FNFMDD
position_column: todo
position_ordinal: '8480'
title: 'Add fan-out queries on CodeContextManager: searchCode/searchSymbol/grepCode across roots'
---
## What
Add workspace-wide query methods to `CodeContextManager` that fan out over every open context concurrently and merge results with root attribution. New file `Sources/FoundationModelsCodeContext/Ops/ManagerQueries.swift` (extension on `CodeContextManager`) plus result wrappers (same file or a small sibling):

- `public struct Rooted<Value: Sendable>: Sendable { public let root: URL; public let value: Value }` — root-qualifies a per-context result (per-context result paths stay root-relative; the wrapper is what disambiguates them).
- `public struct FanOutFailure: Sendable { public let root: URL; public let message: String }` — String payload, matching `CodeContextError`'s Sendable-primitives convention.
- Each method returns results **plus** failures — partial failure must never sink the batch: run all contexts in a `TaskGroup`, catch per-root errors into `FanOutFailure`, return whatever succeeded.

**Merge rule for ALL three ops: rank-major interleave.** Sort the union by (per-root rank ascending, root path ascending as tie-break), then cap. Rationale: `SearchCodeMatch` scores are NOT comparable across roots — `SearchCode.run` returns `RRF.fuse` output normalized to [0,1] **per corpus** (see `Ops/SearchCode.swift` `fuseRankings`), a rank-derived value relative to each root's own chunk population, so merge-by-score would systematically favor small repos. Rank-major interleave also guarantees a union cap samples every root instead of exhausting the alphabetically-first root before repo B contributes. Document the per-root-normalized score caveat on the `searchCode` method.

Methods (thin over the existing per-context ops; mirror their parameter defaults from `CodeContext`):
- `searchCode(query:topK:weights:)` — fan out `CodeContext.searchCode`, wrap each root's matches as `Rooted<...>` (preserving per-root order as rank), interleave, cut to `topK` across the union.
- `searchSymbol(query:kind:maxResults:)` — same shape over `[SearchSymbolMatch]`, `maxResults` across the union.
- `grepCode(pattern:languages:filePattern:maxResults:)` — same shape over `GrepCodeResult`'s matches.

## Acceptance Criteria
- [ ] Each method queries every open context concurrently (TaskGroup), not serially
- [ ] Merged output is rank-major interleaved (every root's before any root's #2), tie-broken by root path, capped across the union
- [ ] A union cap smaller than one root's result count still includes results from every root that had any
- [ ] Every result carries its root; a match from repo A is distinguishable from an identically-pathed match in repo B
- [ ] Single-root failure: corrupting one root's store after `start()` (delete or overwrite `<root>/.code-context/kit.db*` so its next query throws `CodeContextError.storage`) yields that root in `failures` while the other roots' results are returned intact
- [ ] Zero open roots returns empty results and empty failures, no error

## Tests
- [ ] `Tests/FoundationModelsCodeContextTests/ManagerQueriesTests.swift`: two-or-three temp repo fixtures opened through a fake-connection manager with `FakeEmbedder`; assert interleaved merge order, union caps sampling all roots, root attribution on identical relative paths, the corrupted-store partial-failure scenario, and the zero-roots case
- [ ] `swift test --filter ManagerQueriesTests` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.