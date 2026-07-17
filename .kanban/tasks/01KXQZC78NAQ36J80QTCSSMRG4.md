---
position_column: todo
position_ordinal: '80'
title: Adopt Ranker streaming corpus APIs for incremental file re-index
---
## What
Adopt FoundationModelsRanker's streaming corpus APIs (once they land) to make file re-index incremental, replacing today's generation-invalidated wholesale reload.

Today: any store write bumps `generation`, and `SearchCorpus.snapshot()` responds by reloading the entire corpus from GRDB — every `ts_chunks` row re-fetched, every `RankedDocument` re-tokenized, the full embedding matrix repacked — even when a single file changed.

After adoption: a file re-index becomes `remove(group: filePath)` + `add(reparsedChunks)` on the Ranker's mutable streaming corpus — O(changed file), not O(corpus):
- The lexical corpus (RankedDocument precompute + BM25 corpus globals) mutates additively via the Ranker API; no per-save whole-corpus re-tokenize.
- The group key is the chunk's `filePath` (the Ranker API's group key is generic — FoundationModelsAgents uses session ids for the same mechanism).
- The packed vDSP cosine matrix stays CCK-side and is repacked wholesale on mutation — cheap memcpy of already-persisted vectors, no re-embedding. (Additive matrix mutation is the separate, reserved `CosineScoring` phase-2 seam in the Ranker plan; not this task.)
- GRDB remains the durable store exactly as-is: rows and embedding blobs unchanged; only the in-memory corpus lifecycle changes.

**Prerequisite (cross-repo):** FoundationModelsRanker tasks on its board — `xqrbq19` (streaming corpus: additive add/remove with incremental BM25 globals), plus its dependents (actor confinement, incremental embed on add). Do not start until `xqrbq19` is done and published on the Ranker `main` branch.

## Acceptance Criteria
- [ ] Re-indexing one file no longer triggers a whole-corpus reload: only that file's chunks are removed/re-added in the in-memory corpus
- [ ] Search results after an incremental file update are identical to results after a from-scratch snapshot load of the same store state (equivalence)
- [ ] BM25 globals (idf/avgdl) correct after incremental updates — asserted against a from-scratch rebuild
- [ ] Cosine still works: matrix repacked from persisted vectors on mutation; no embed calls during re-index of unchanged chunks
- [ ] Generation-based full reload remains as the cold-start path (first load) and as a fallback

## Tests
- [ ] Incremental-vs-wholesale equivalence: edit one file, compare search results and BM25 globals against a fresh `snapshot()` load
- [ ] Counting fake embedder: file re-index with unchanged embeddings performs zero embed calls
- [ ] Perf guard: re-index of one file in a many-file corpus does not re-tokenize untouched files' chunks (observable via instrumentation or a counting seam)

## Workflow
- Use /tdd — write failing tests first, then implement to make them pass.