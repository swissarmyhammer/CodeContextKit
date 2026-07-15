---
assignees:
- claude-code
depends_on:
- 01KXK6VNT8YNZYEJB0KMM19ANQ
position_column: todo
position_ordinal: '8680'
title: 'Add example program: multi-root CodeContextManager'
---
## What
Add the second "way in" example: an executable demonstrating `CodeContextManager` over several repos.

- `Package.swift`: add `.executableTarget(name: "ManagerExample", dependencies: [.target(name: packageName), .product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")], path: "Examples/ManagerExample")`. The Router product is required for embedder resolution — same rationale as the CodeContextExample task: the library ships no embedder factory; the host resolves a `RoutedEmbedder` and wraps it in `RoutedEmbedderAdapter`.
- `Examples/ManagerExample/main.swift`: take a parent directory as `CommandLine.arguments[1]` and an optional query argument, then:
  1. resolve the embedder via FoundationModelsRouter and create `CodeContextManager(embedder:)`
  2. `RootDiscovery.discoverRoots(under: parent)` — print each discovered repo root
  3. open each via `manager.context(for:)`; print each root's ready state from `manager.state`
  4. demonstrate lazy routing: `try await manager.context(containing:)` for one file path inside a discovered repo
  5. run the fan-out `manager.searchCode(query:)` and print `Rooted` results (root + relative path + score) plus any `FanOutFailure`s
  6. `await manager.shutdown()`

Same constraints as the standalone example: public API of the two packages only (no `@testable`), thin script, exists to compile-verify and document the manager entry point.

## Acceptance Criteria
- [ ] `swift build` builds the `ManagerExample` target with no warnings
- [ ] The source demonstrates discovery, explicit open, lazy `context(containing:)`, fan-out search with root-qualified output, and shutdown — all via public API (no `@testable`)

## Tests
- [ ] `swift build` exits 0 with the new target included — the build is the automated verification (a live run needs Apple Intelligence + real LSP daemons, so it is a documented local smoke step in the example's header comment, NOT an acceptance gate)
- [ ] `swift test` still passes

## Workflow
- Use `/tdd` where applicable; for this example the build itself is the failing-then-passing check.