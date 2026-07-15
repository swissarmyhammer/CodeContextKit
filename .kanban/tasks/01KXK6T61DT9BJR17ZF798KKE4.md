---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: 'Add ManagerState: @Observable aggregate of per-root CodeContextState'
---
## What
Create `Sources/FoundationModelsCodeContext/ManagerState.swift` with a `@MainActor @Observable public final class ManagerState`, mirroring `CodeContextState`'s conventions exactly (all stored properties `private(set)`, mutations only through `nonisolated` async `publish*` methods that hop to the main actor via `MainActor.run` and are awaitable):

- `public private(set) var contexts: [URL: CodeContextState]` — one entry per open root, keyed by standardized root URL.
- `public var roots: [URL]` — computed, sorted by path, for stable SwiftUI iteration.
- `public var isReady: Bool` — computed: `contexts.values.allSatisfy(\.isReady)` (vacuously true when empty; document this the same way `CodeContextState.isReady` documents its vacuous initial state). Because each `CodeContextState` is itself `@Observable`, reading `isReady` inside a SwiftUI view tracks through to every child state.
- `public nonisolated func publishOpened(root: URL, state: CodeContextState) async`
- `public nonisolated func publishClosed(root: URL) async`

## Acceptance Criteria
- [ ] `publishOpened`/`publishClosed` add and remove entries; `roots` stays sorted
- [ ] `isReady` is true when empty, false while any child's indexing/servers are unsettled, true once every child is ready
- [ ] All stored properties are `private(set)`; the only mutation paths are the publish methods

## Tests
- [ ] `Tests/FoundationModelsCodeContextTests/ManagerStateTests.swift`: open/close bookkeeping, sorted `roots`, `isReady` aggregation driven by publishing real `IndexProgress`/`ServerStatus` values into child `CodeContextState` instances (reuse the patterns from the existing `CodeContextState` tests)
- [ ] `swift test --filter ManagerStateTests` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.