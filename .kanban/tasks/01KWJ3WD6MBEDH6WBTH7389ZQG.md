---
depends_on:
- 01KWJ3VER6934379BZKH1ZXGJN
position_column: todo
position_ordinal: '9480'
title: 'findDuplicates op: meta-type-aware near-duplicate detection'
---
## What
Create `Sources/CodeContextKit/Ops/FindDuplicates.swift` — port of `ops/find_duplicates.rs` with the meta-type constraint from plan.md. Reuse the `SearchCorpus` matrix, partitioned by chunk `kind`: candidates are compared **only within their own meta-type** (methods and functions share a partition; types their own). Workspace scope = per-partition matrix–matrix similarity; file scope (`findDuplicates(file:minSimilarity:)`, default 0.85) = one matvec per source chunk in that file. Exclude self-pairs and same-symbol pairs; return `FindDuplicatesResult { groups: [DuplicateGroup(source, duplicates: [(chunk, similarity)])] }` sorted by similarity.

## Acceptance Criteria
- [ ] Two near-identical fixture functions are grouped; a type with cosine above threshold against a function is NOT reported (cross-meta-type suppressed)
- [ ] minSimilarity threshold honored; self-pairs never reported
- [ ] File scope returns only groups whose source chunk is in the given file

## Tests
- [ ] `Tests/CodeContextKitTests/FindDuplicatesTests.swift` with FakeEmbedder-seeded corpus: duplicate grouping golden, cross-meta-type suppression, threshold and scope behavior
- [ ] Run `swift test --filter FindDuplicatesTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.