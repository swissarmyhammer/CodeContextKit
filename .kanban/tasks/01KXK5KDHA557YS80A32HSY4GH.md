---
comments:
- actor: claude-code
  id: 01kxk7s1fvh0n8zkzzx3e12x5f
  text: |-
    Implemented.

    Sources/FoundationModelsCodeContext/Diagnostics/DiagnosticRecord.swift:
    - DiagnosticRecord: struct -> public struct; all seven stored properties (path, range, severity, message, code, source, containingSymbol) -> public. No public init added (per task).
    - Counts: struct -> public struct; errors/warnings -> public. No public init added.
    - DiagnosticsReport: records/counts/pending -> public (struct was already public). Added a DocC note documenting it as a sibling-consumable value type.
    - Sendable/Equatable conformances left untouched. Verified DiagnosticRecord's own field types (LSPRange, DiagnosticSeverity) were already public, so no further widening was needed to make this compile.

    Tests/FoundationModelsCodeContextTests/DiagnosticsReportPublicVisibilityTests.swift (new):
    - Uses a plain `import FoundationModelsCodeContext` (no @testable) - the only suite in the target that does.
    - Obtains a real DiagnosticsReport via the public CodeContext(rootDirectory:, embedder:) init -> start() -> diagnostics(scope:) facade, in a temp workspace with no project-marker file (so ProjectDetection finds nothing, no LSP daemon spawns, live session resolves to nil - mirrors DiagnosticsTests.noSessionMeansNoLiveLayerAndNeverPending).
    - Reads report.records.map(\.message), report.counts.errors, report.pending - proving these compile without @testable.
    - Note: DiagnosticsOps/LspSession (the internal fake-connection seam other suites use directly) stay internal by design; CodeContext's public init only supports ProcessLanguageServerConnection, so this is the actual reachable non-@testable path to a DiagnosticsReport, not the literal FakeLanguageServerConnection seam the task description mentioned.

    Verification: `swift build` exit 0. `swift test` full suite green twice in a row (441 tests, 37 suites, 0 failures). One earlier run had a single flaky failure in ConnectionTests (a suite whose own header comment documents occasional flakiness under load from real subprocess spawning) - unrelated to this change, not reproduced on reruns. Adversarial double-check agent independently re-ran build+test and reviewed the diff: verdict PASS, no findings.

    Leaving in doing for /review.
  timestamp: 2026-07-15T15:54:24.635639+00:00
position_column: done
position_ordinal: a580
title: Make DiagnosticsReport contents public (records/counts/pending, DiagnosticRecord, Counts)
---
## What
Make the contents of `DiagnosticsReport` publicly readable so sibling packages can consume it without `@testable import`. Requested by a downstream consumer (FoundationModelsFileTool), which needs to read a `DiagnosticsReport` returned across the module boundary.

File: `Sources/FoundationModelsCodeContext/Diagnostics/DiagnosticRecord.swift`

Current state (verified 2026-07-15):
- `DiagnosticsReport` is already `public` (line ~130) BUT its stored properties `records`, `counts`, `pending` are internal (`let` with no access modifier) — so a non-`@testable` consumer cannot read them.
- `DiagnosticRecord` is an internal `struct` (line ~12); its stored properties (`path`, `range`, `severity`, `message`, `code`, `source`, `containingSymbol`) are internal.
- `Counts` is an internal `struct` (line ~96); its stored properties (`errors`, `warnings`) are internal.

## Changes
- Make `DiagnosticsReport.records`, `.counts`, `.pending` `public`.
- Make `DiagnosticRecord` `public`, and make its stored properties `public`.
- Make `Counts` `public`, and make its stored properties `public`.
- A public `init` is NOT required (consumers only read values received across the seam).
- Add a DocC note on `DiagnosticsReport` stating it is a sibling-consumable value type (completes the package's stated "Tool-ready" intent).
- Keep `Sendable`/`Equatable` conformances intact.

## Acceptance Criteria
- [ ] A downstream (non-`@testable`) `import FoundationModelsCodeContext` can compile `report.records.map(\.message)`, `report.counts.errors`, and `report.pending`.
- [ ] `swift build` and `swift test` in FoundationModelsCodeContext remain green.

## Tests
- [ ] Add an upstream test that uses a plain `import FoundationModelsCodeContext` (NO `@testable`), constructs/receives a `DiagnosticsReport` via the existing fake-connection seam, and reads `records` / `counts` / `pending` — proving public visibility from outside the module.
- [ ] Run `swift test` — expect green.

## Workflow
- Use `/tdd` — write the failing non-@testable visibility test first, then widen access to make it pass.

## Provenance
Filed from the FoundationModelsFileTool plan (its task "Upstream PR: make DiagnosticsReport contents public", short id hkq2gff). FileTool is the downstream consumer and is blocked on this visibility change. When done here, unblock/close hkq2gff on the FileTool board.