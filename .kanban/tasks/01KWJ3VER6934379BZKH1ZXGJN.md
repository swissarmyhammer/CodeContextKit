---
comments:
- actor: wballard
  id: 01kwm35qdxhqkkd9bzcpj5q6dd
  text: |-
    Implemented and green.

    Built:
    - `Sources/CodeContextKit/Search/SearchCorpus.swift` — `SearchCorpusSnapshot` (contiguous row-major `[Float]` embedding matrix + id/kind/etc sidecar arrays + precomputed per-chunk BM25 weighted-term-frequency/term-set and trigram-set data) and `SearchCorpus` actor (lazy load from `ts_chunks`, cached, invalidated by `Store.generation`).
    - `Sources/CodeContextKit/Ops/SearchCode.swift` — `SearchWeights`, `IndexingProgress`, `SearchCodeMatch`, `SearchCodeResult`, and `SearchCode.run(corpus:embedder:query:topK:weights:)`: embeds the query, ranks BM25/trigram/cosine independently, fuses via `RRF.fuse`/`RRF.normalize` (only signals with a positive weight and a non-empty ranking enter the fusion, so the normalization ceiling stays reachable), returns Hits + optional `IndexingProgress`.
    - `Sources/CodeContextKit/Index/Store.swift` — added a `Store.generation` write-generation counter (lock-guarded private `GenerationCounter` class, since `Store` claims plain `Sendable`). Bumped unconditionally on every successful `write(_:)` call rather than at specific TreeSitterWorker call sites — one choke point that can't drift out of sync as new write paths are added, at the cost of occasionally over-invalidating the corpus cache on unrelated writes (cheap and safe).
    - `Sources/CodeContextKit/Search/Trigram.swift` — added `Trigram.dice(querySet:targetSet:)` overload over precomputed sets (existing `dice(query:target:)` now delegates to it), so `SearchCorpus` can precompute chunk trigram sets once and reuse them across queries.

    Deviations / notes:
    - Used `vDSP_mmul` instead of `cblas_sgemv` for the matvec — `cblas_sgemv` is deprecated on this macOS/Accelerate version (ILP64 migration warning); plan.md explicitly names `cblas_sgemv`/`vDSP` as alternatives, so this stays within the letter and spirit of the plan while keeping the build warning-free.
    - `Hit`/`Signals` (from an earlier task) aren't `Codable`, so `SearchCodeMatch`/`SearchCodeResult` follow suit (`Sendable`+`Equatable` only) rather than partially conforming.
    - Semantic-only test fixture uses digit-only filler text with a hand-crafted embedding vector (FakeEmbedder is hash-based, not real semantics, so lexical-overlap-free + embedding-identical-to-query is the only way to isolate the cosine signal in a test).

    Verification: `swift test --filter Search` → 12/12 new tests pass. Full `swift test` → 293/293 pass (one run hit a known-flaky `ConnectionTests` process-spawn contention failure documented in that file; reran clean, confirmed unrelated to this change). `swift build` → zero warnings.

    Review tool (`mcp__sah__review`) flagged and I fixed: fuseRankings' three parallel if-blocks → data-driven loop over `[(ranking, weight)]`; matvec's 5-level nested guard → extracted `multiplyMatrixByVector` helper. It also flagged pre-existing `dbPool`/`withDbAccess`/`dbPoolMethod` abbreviations in `Store.swift` — left alone as out-of-scope pre-existing naming, not part of this task's diff.

    Leaving in `doing` for review.
  timestamp: 2026-07-03T13:37:30.045123+00:00
depends_on:
- 01KWJ3Q0SYT3GQ98YBMZDRJYXA
- 01KWJ3T4CGTNK4BZSE78FSWYFH
position_column: doing
position_ordinal: '80'
title: 'SearchCorpus and searchCode op: Accelerate cosines + RRF wiring'
---
## What\nCreate `Sources/CodeContextKit/Search/SearchCorpus.swift` + `Sources/CodeContextKit/Ops/SearchCode.swift` per plan.md \"Search\". `SearchCorpus`: contiguous N×dim `[Float]` matrix of embedded chunks (id + kind sidecar arrays) plus tokenized BM25/trigram structures, loaded lazily from `ts_chunks`, invalidated by a store generation counter bumped on index writes. Cosine scoring = one `cblas_sgemv` matvec (vectors L2-normalized so cosine == dot). `searchCode(query:topK:weights:)`: embed query via injected `TextEmbedding`, rank three signals, fuse with RRF (K=60), normalize to [0,1], return Hits with per-signal `Signals`; embeddings incomplete → keyword-only + `IndexingProgress` note.\n\n## Acceptance Criteria\n- [x] Matvec cosine equals scalar dot-product reference within 1e-5 across random normalized fixtures\n- [x] Generation-counter staleness: indexing a new file then searching returns the new chunk without restarting\n- [x] With a nil embedder, searchCode returns keyword-ranked hits and a non-nil IndexingProgress\n\n## Tests\n- [x] `Tests/CodeContextKitTests/SearchCodeTests.swift` with FakeEmbedder: end-to-end relevance goldens on a fixture corpus (semantic-only hit found via cosine, keyword-only hit via BM25, fused ordering), matvec-vs-scalar equivalence, staleness reload, degraded mode\n- [x] Run `swift test --filter SearchCodeTests` → all pass\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.\n\n## Implementation note\nUsed `vDSP_mmul` instead of `cblas_sgemv` (deprecated on this Accelerate version in favor of an ILP64 interface); plan.md names both as acceptable alternatives for this scoring step. See task comments for full implementation notes.