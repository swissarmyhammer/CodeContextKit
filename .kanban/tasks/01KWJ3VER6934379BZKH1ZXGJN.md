---
depends_on:
- 01KWJ3Q0SYT3GQ98YBMZDRJYXA
- 01KWJ3T4CGTNK4BZSE78FSWYFH
position_column: todo
position_ordinal: '9180'
title: 'SearchCorpus and searchCode op: Accelerate cosines + RRF wiring'
---
## What
Create `Sources/CodeContextKit/Search/SearchCorpus.swift` + `Sources/CodeContextKit/Ops/SearchCode.swift` per plan.md "Search". `SearchCorpus`: contiguous N×dim `[Float]` matrix of embedded chunks (id + kind sidecar arrays) plus tokenized BM25/trigram structures, loaded lazily from `ts_chunks`, invalidated by a store generation counter bumped on index writes. Cosine scoring = one `cblas_sgemv` matvec (vectors L2-normalized so cosine == dot). `searchCode(query:topK:weights:)`: embed query via injected `TextEmbedding`, rank three signals, fuse with RRF (K=60), normalize to [0,1], return Hits with per-signal `Signals`; embeddings incomplete → keyword-only + `IndexingProgress` note.

## Acceptance Criteria
- [ ] Matvec cosine equals scalar dot-product reference within 1e-5 across random normalized fixtures
- [ ] Generation-counter staleness: indexing a new file then searching returns the new chunk without restarting
- [ ] With a nil embedder, searchCode returns keyword-ranked hits and a non-nil IndexingProgress

## Tests
- [ ] `Tests/CodeContextKitTests/SearchCodeTests.swift` with FakeEmbedder: end-to-end relevance goldens on a fixture corpus (semantic-only hit found via cosine, keyword-only hit via BM25, fused ordering), matvec-vs-scalar equivalence, staleness reload, degraded mode
- [ ] Run `swift test --filter SearchCodeTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.