---
comments:
- actor: wballard
  id: 01kwph51fkmvsxy870d7fne6dg
  text: |-
    Research complete. Key findings:

    - Rust reference found at /Users/wballard/github/swissarmyhammer/swissarmyhammer/crates/swissarmyhammer-diagnostics/src/{diagnose,settle,record,config}.rs. Scope resolution (git status/glob/sha) lives in the *caller* (crates/swissarmyhammer-tools/.../diagnostics/mod.rs), not in the diagnostics crate itself, and uses git2 (libgit2) — this Swift port has no git2 dependency, so scope resolution will shell out to the `git` CLI via Process (matching ProcessLanguageServerConnection's spawn style), documented as a deliberate divergence.
    - LspSession (Sources/CodeContextKit/LSP/LspSession.swift) already has everything needed: syncOpen, pullDiagnostics, diagnosticUpdates() (AsyncStream, multi-subscriber), diagnostics(for:), isReady. No isRunning — "not running" is modeled as `session: LspSession<Connection>? == nil`, matching LiveOpsCore's convention.
    - DiagnosticSeverity already exists (LSPTypes.swift): .error=1/.warning=2/.information=3/.hint=4 — severity floor = "rawValue <= floor.rawValue".
    - BlastRadiusOps.blastRadius(store:file:symbol:maxHops:) (Ops/BlastRadius.swift) is the one-hop-dependents primitive; call with maxHops:1, symbol:nil, collect hop symbols' filePath excluding self.
    - No git-status precedent in this codebase at all (grep came up empty) — new pattern, modeled on ProcessLanguageServerConnection's Process/Pipe spawn style but as one-shot commands (not the persistent raw-fd reader).
    - Clock injection pattern confirmed: `any Clock<Duration> = ContinuousClock()` (LSPIndexWorker, ProcessLanguageServerConnection); tests use Tests/CodeContextKitTests/Support/ManualClock.swift with `waitForWaiter()`/`advance(by:)`. For the settle engine's absolute hard-deadline + resettable debounce-deadline race, existentials can't expose `.now`/Instant cleanly, so Settle's internal race functions are generic over `<C: Clock>` instead of using `any Clock<Duration>` — the public entry point still takes `any Clock<Duration> = ContinuousClock()` for ergonomics and forwards into the generic implementation (relying on Swift's implicit existential opening, SE-0352).
    - AsyncStream cancellation semantics for racing stream-updates against timers were not something I wanted to gamble on, so Settle uses a small cancellation-safe `UpdateMailbox` actor (modeled directly on ManualClock's own waiter/continuation pattern already trusted in this codebase) fed by a persistent unstructured drain Task, rather than racing `AsyncStream.next()` directly inside a TaskGroup.

    Proceeding with TDD: writing DiagnosticsTests.swift first (failing), then implementing Sources/CodeContextKit/Diagnostics/.
  timestamp: 2026-07-04T12:20:16.499107+00:00
depends_on:
- 01KWJ3S972X06D1TKBDBCVB3SD
- 01KWJ3VNKRFPHF36XXH740CWZM
position_column: doing
position_ordinal: '80'
title: 'Diagnostics op: settle engine, scopes, dependents fold-in'
---
## What
Create `Sources/CodeContextKit/Diagnostics/` — port of `crates/swissarmyhammer-diagnostics/{diagnose,settle,record}.rs`. `diagnostics(scope:severity:)` with `.workingTree` (git status: modified+untracked+staged), `.file(glob)`, `.sha(range)` scopes and a **severity floor parameter defaulting to `.warning`** (records below the floor excluded; lowering to `.hint` includes everything); paths absolutized, confined to root, filtered to diagnosable extensions. For each target: syncOpen + pullDiagnostics, then the settle engine — subscribe to the session diagnostics stream, seed from cache, `Settled` after 300ms quiescence, `Pending` at 5s hard timeout (injectable clock). Dependents: one-hop inbound via blastRadius; only **broken** dependents (≥1 error/warning) fold in, ranked errors-then-warnings, capped at 100 per report. `pending: true` when settle timed out or session `!isReady`. `DiagnosticsReport { records, counts, pending }`.

## Acceptance Criteria
- [ ] Manual-clock settle: an update at t+200ms restarts the quiescence window; silence to t+300ms → Settled; continuous updates → Pending at 5s
- [ ] Severity floor: hint/info diagnostics excluded at the default `.warning` floor, included when the floor is lowered to `.hint`
- [ ] Clean dependents are excluded; broken dependents appear ranked after queried files
- [ ] Server running but not ready → report flagged pending even if empty

## Tests
- [ ] `Tests/CodeContextKitTests/DiagnosticsTests.swift`: settle timing matrix with manual clock; severity floor filtering; scope resolution against a temp git repo fixture; dependents fold-in with seeded call edges; pending flag truth table
- [ ] Run `swift test --filter DiagnosticsTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.