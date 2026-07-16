---
position_column: todo
position_ordinal: '8580'
title: Make CodeContext.rootDirectory public (public nonisolated let) for sibling path-rebasing
---
## What
Make `CodeContext.rootDirectory` publicly readable so a sibling package can learn which workspace root a resolved context is rooted at.

File: `Sources/FoundationModelsCodeContext/CodeContext.swift`

Current state (verified 2026-07-16 at main `179fc05`):
- Line ~32: `private let rootDirectory: URL` — internal only.
- `CodeContext` is an actor; `rootDirectory` is an immutable `let` set once in `init(rootDirectory:embedder:)` and never mutated.
- `CodeContextManager` (`context(containing:openIfNeeded:)`, `context(ancestorOf:)`) and public `DiagnosticsReport` members (`records`/`counts`/`pending`, `DiagnosticRecord`, `Counts`) already exist and are public — this is the one remaining visibility gap.

## Change
- Make the stored property publicly readable: `public nonisolated let rootDirectory: URL`.
  - `nonisolated` is safe and required here: the value is an immutable `let` on an actor, so synchronous cross-actor reads are data-race-free, and consumers need to read it without `await`.
  - Keep the setter private (a `let` has no setter, so `public nonisolated let` already gives read-only public access — do NOT add a public initializer or make it `var`).
- Add a one-line DocC note that it exposes the workspace root the context is rooted at, for sibling packages that must rebase context-relative paths to their own root.

## Why (downstream consumer: FoundationModelsFileTool)
The FileTool DiagnosticsBridge needs the OUTPUT side, not the input: `DiagnosticsScope.file` already accepts absolute paths, but every `DiagnosticRecord.path` in a returned report is relative to the RESOLVED context's workspace root. To rebase those to session-root-relative, the sibling package must read which root the resolved context is rooted at. `rootDirectory` is the minimal change. (Alternative if preferred: a `CodeContextManager` API returning `(root, context)` pairs — but exposing `rootDirectory` is smaller.)

## Acceptance Criteria
- [ ] `CodeContext.rootDirectory` is `public nonisolated let` (read-only public); no new public initializer added.
- [ ] `swift build` and `swift test` in FoundationModelsCodeContext remain green.
- [ ] A downstream (non-`@testable`) `import FoundationModelsCodeContext` can read `context.rootDirectory` synchronously (no `await`).
- [ ] Change committed and pushed to `main` (so a downstream `swift package update` pins a revision containing it).

## Tests
- [ ] Add/confirm an upstream test (plain `import`, no `@testable`) that constructs a `CodeContext` and reads `.rootDirectory` synchronously, asserting it equals the root passed to `init`.
- [ ] Run `swift test` in FoundationModelsCodeContext — expect: green.

## Workflow
- Use `/tdd` — write the failing non-@testable read test first, then widen access to make it pass.

## Provenance
Filed from the FoundationModelsFileTool plan. FileTool task "Upstream: expose CodeContext.rootDirectory publicly + bump pin" (short id hkq2gff) is blocked on this. When done here (committed + pushed to main), FileTool runs `swift package update FoundationModelsCodeContext` and closes hkq2gff (which also carries an in-FileTool visibility-probe test). Companion to the earlier CodeContext task that made DiagnosticsReport public (short id 2hsy4gh), now done.