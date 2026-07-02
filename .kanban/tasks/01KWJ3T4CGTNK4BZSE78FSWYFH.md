---
depends_on:
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: todo
position_ordinal: 8d80
title: 'Embedding seam: TextEmbedding protocol, fake, RoutedEmbedder adapter, worker integration'
---
## What
Create `Sources/CodeContextKit/Embedding/TextEmbedding.swift` (`protocol TextEmbedding: Sendable { var dimension: Int; func embed(_ texts: [String]) async throws -> [[Float]] }`), `RoutedEmbedderAdapter.swift` (wraps FoundationModelsRouter's `RoutedEmbedder` — pure pass-through), and `Tests/.../Support/FakeEmbedder.swift` (deterministic hash-based L2-normalized vectors, configurable dimension). Integrate into the tree-sitter worker: batch-embed chunk texts after parsing, write via the store's embedding codec, set `embedded = 1` only when every chunk embedded; embedder absent/throwing → chunks persist with NULL embedding and `embedded = 0` (graceful skip). Record embedder dimension in the `meta` table; on mismatch with stored dimension, mark all chunks un-embedded for re-embedding.

## Acceptance Criteria
- [ ] Worker with FakeEmbedder produces normalized vectors of the configured dimension for every chunk
- [ ] Worker with a throwing embedder still writes chunks (NULL embedding, embedded=0) and logs, no crash
- [ ] Changing FakeEmbedder dimension between runs triggers full re-embed via the meta-table check

## Tests
- [ ] `Tests/CodeContextKitTests/EmbeddingSeamTests.swift`: happy path, graceful-skip path, dimension-change re-embed; FakeEmbedder determinism (same text → same vector)
- [ ] Run `swift test --filter EmbeddingSeamTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.