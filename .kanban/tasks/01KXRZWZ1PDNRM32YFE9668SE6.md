---
assignees:
- claude-code
depends_on:
- 01KXQZC78NAQ36J80QTCSSMRG4
position_column: todo
position_ordinal: '8180'
title: Use FoundationModelsRanker streaming/updateable index directly instead of the hand-rolled cosine matrix
---
Follow-up to ^cssmrg4. That task adopted the Ranker *additive streaming pattern* plus the `RankedDocument` primitive, but deliberately did NOT wrap `FoundationModelsRanker.SearchCorpus` directly — it kept a hand-rolled per-file cache + packed cosine matrix in `Sources/FoundationModelsCodeContext/Search/SearchCorpus.swift`. The stated reason: Ranker's `add()` hardcodes the item id as the BM25/trigram primary field, whereas this corpus needs the chunk's symbol path as the primary field (the `symbolPathMatchOutranksBodyOnlyMatch` test depends on it) alongside a separate int64 id and packed cosine matrix.

Goal (per user directive 2026-07-17): actually use Ranker's streaming / updateable index APIs for the incremental re-index path, rather than maintaining a parallel hand-rolled index.

Scope to investigate:
- Review the updated FoundationModelsRanker (main, streaming corpus / updateable index APIs) at .build/checkouts/FoundationModelsRanker.
- Determine whether Ranker's updateable index now supports a distinct primary-field/id separation (or a config) that satisfies the symbol-path-outranks-body requirement. If yes, replace the hand-rolled matrix with Ranker's updateable index.
- Preserve all existing SearchCorpus behavior and tests (symbolPathMatchOutranksBodyOnlyMatch, cosine equivalence, incremental equivalence, deletion, dimension-change regression).
- If Ranker genuinely cannot express the primary-field requirement, document that as a blocker with the specific API gap and stop.

Verify: `swift build`, `swift test` fully green; format with `swift format -i -r Sources Tests`.