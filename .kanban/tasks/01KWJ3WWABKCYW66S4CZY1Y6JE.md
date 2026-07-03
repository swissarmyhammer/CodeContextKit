---
comments:
- actor: wballard
  id: 01kwmtqxnc4pj8k8mzyw1jqt8a
  text: |-
    Implemented via /tdd. Wrote Tests/CodeContextKitTests/CodeContextStateTests.swift first (16 tests), watched it fail to compile (CodeContextState didn't exist — RED), then implemented Sources/CodeContextKit/CodeContextState.swift (GREEN).

    Built:
    - `IndexProgress` (public struct): filesWalked/filesParsed/filesEmbedded/filesLspIndexed counts + `isDrained` (all layers caught up to filesWalked).
    - `CodeContextState` (`@MainActor @Observable public final class`): rootDirectory, projects, servers, indexing, diagnostics, isReady — all `public private(set)`.
    - Publisher API: `publishProjects`/`publishServers`/`publishIndexing`/`publishDiagnostics`, all `nonisolated func ... async` that internally `await MainActor.run { ... }` (per task's suggested shape), so callers/tests can await the mutation landing rather than fire-and-forget.
    - `isReady` = `IndexProgress.isDrained && servers.allSatisfy(isSettled)`, computed via a private exhaustive switch (`isSettled(_:)`) treating `.running`/`.notFound` as settled and `.failed` as settled once `attempts >= 5` (mirrors LspDaemon's private `maxConsecutiveFailures`, duplicated with a doc comment explaining why — LspDaemon never exposes it).
    - `publishDiagnostics` replaces `diagnostics[uri]` wholesale (dictionary subscript assign), never appends.

    Deviation from literal plan.md types: `ServerStatus` (LspSupervisor.swift) and `LspDaemonState` (LspDaemon.swift) were `internal`, not `public`. Since plan.md's CodeContextState literally stores `[ServerStatus]` and the class itself must be public for SwiftUI consumption, elevated both to `public` (struct/enum + stored properties + inits — visibility-only change, zero logic touched, confirmed via diff). No other file references these types outside LSP/LspSupervisor.swift and LSP/LspDaemon.swift.

    Ran the double-check agent (via really-done's adversarial gate) — it flagged that `isReady` starts `true` immediately after `init` (vacuous truth: IndexProgress.zero.isDrained + empty servers.allSatisfy both trivially true), with no test or doc comment calling this out as intentional. Fixed by documenting it explicitly on both `isReady` and `init`'s doc comments, and adding a locking test (`isReadyTrueImmediatelyAfterConstruction`) so the behavior is asserted, not accidental. Re-ran double-check-equivalent reasoning myself after the fix; no further findings.

    Verification: `swift build` clean (zero warnings beyond a pre-existing unrelated mlx-swift bundle warning). `swift test --filter CodeContextStateTests` → 16/16 pass. Full `swift test` → 354/354 pass, 29 suites (one transient run hit a known pre-existing ConnectionTests spawn-contention flake documented in that file's own comments — unrelated to this change, passed clean on retry).

    Note: this session's LSP diagnostics MCP tool (`mcp__sah__diagnostics`) is unavailable ("not the leader for this workspace") — an environment/infra issue, not related to this change; relied on `swift build`/`swift test` directly instead.

    Leaving task in `doing` for review per /implement workflow.
  timestamp: 2026-07-03T20:29:23.500273+00:00
depends_on:
- 01KWJ3VY63EM20R393B7REJSFY
- 01KWJ3S2AJFZPWWXRTKSQC3TW7
position_column: doing
position_ordinal: '80'
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