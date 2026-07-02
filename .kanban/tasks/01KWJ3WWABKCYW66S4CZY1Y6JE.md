---
depends_on:
- 01KWJ3VY63EM20R393B7REJSFY
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: todo
position_ordinal: '9680'
title: 'CodeContextState: @Observable unified state'
---
## What
Create `Sources/CodeContextKit/CodeContextState.swift` — the `@MainActor @Observable` class per plan.md: `rootDirectory`, `projects: [DetectedProject]`, `servers: [ServerStatus]`, `indexing: IndexProgress` (walked/parsed/embedded/lsp-indexed counts per layer), `diagnostics: [DocumentURI: [Diagnostic]]`, `isReady`. Internal publisher API (nonisolated funcs hopping to MainActor) that the workers, supervisor health loop, and session diagnostics streams call. `isReady` derives from all-layers-drained + all-servers-settled (running / notFound / permanently failed).

## Acceptance Criteria
- [ ] Publishing a daemon state change updates `servers` on the main actor; SwiftUI observation fires (verified via `withObservationTracking`)
- [ ] `isReady` flips true only when index counts are drained AND every server is settled
- [ ] Diagnostics publish replaces per-URI arrays, not appends

## Tests
- [ ] `Tests/CodeContextKitTests/CodeContextStateTests.swift`: publisher → main-actor mutation, observation firing via withObservationTracking, isReady truth table, per-URI replacement
- [ ] Run `swift test --filter CodeContextStateTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.