---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: 'Add example program: standalone single-root CodeContext'
---
## What
Add the first of the two "ways in" examples: a small executable demonstrating standalone `CodeContext` on one repo (this entry point stays public and first-class).

- `Package.swift`: add `.executableTarget(name: "CodeContextExample", dependencies: [.target(name: packageName), .product(name: "FoundationModelsRouter", package: "FoundationModelsRouter")], path: "Examples/CodeContextExample")` following the manifest's named-constant conventions. The Router product is required: this package deliberately ships no embedder factory — `RoutedEmbedderAdapter`'s public init takes an already-resolved `RoutedEmbedder`, and plan.md records that the host app resolves the Router profile and injects the embedder. Do NOT add the example to the library product.
- `Examples/CodeContextExample/main.swift`: take a root directory as `CommandLine.arguments[1]` (default: current directory) and an optional query argument. Resolve a `RoutedEmbedder` via FoundationModelsRouter's public resolution API and wrap it in `RoutedEmbedderAdapter`, then:
  1. `let context = try await CodeContext(rootDirectory:embedder:)` + `try await context.start()`
  2. print detected projects and `indexStatus()`
  3. run `searchSymbol` and `searchCode` with the query and print results
  4. `await context.stop()`

Keep `main.swift` a thin script over the public API of the two packages (`import FoundationModelsCodeContext`, `import FoundationModelsRouter`; no `@testable`) — it exists to compile-verify and document the public surface, not to hold logic.

## Acceptance Criteria
- [ ] `swift build` builds the `CodeContextExample` target with no warnings
- [ ] The example uses only public API of FoundationModelsCodeContext and FoundationModelsRouter (no `@testable`)
- [ ] The source demonstrates the full lifecycle: embedder resolution → init → start → queries → stop

## Tests
- [ ] `swift build` exits 0 with the new target included — this build is the automated verification (running the example needs Apple Intelligence + real LSP daemons, so a live run is a documented local smoke step in the example's header comment, NOT an acceptance gate)
- [ ] `swift test` still passes (no library changes expected)

## Workflow
- Use `/tdd` where applicable; for this example the build itself is the failing-then-passing check.