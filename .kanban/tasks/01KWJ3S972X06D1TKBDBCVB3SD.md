---
depends_on:
- 01KWJ3RB07JNW5QXZNH1ESMH2F
position_column: todo
position_ordinal: 8a80
title: 'LspSession actor: document sync, diagnostics cache, readiness'
---
## What
Create `Sources/CodeContextKit/LSP/LspSession.swift` — port of `crates/swissarmyhammer-lsp/src/session.rs` as an actor over a `LanguageServerConnection`. Open-document set with `DocState(version, textHash)`; `syncOpen(path, text)` opens-or-refreshes, suppresses duplicate opens and no-op changes by hash compare; consumes `serverNotifications` to maintain a per-URI diagnostics cache fanned out via `AsyncStream<DiagnosticUpdate>` (multi-subscriber); `pullDiagnostics(uri:)`; `isReady` flag flipped false on ServerCancelled/ContentModified "still loading" replies and true on clean responses; `resetDocuments()` clears the doc set and cache (restart correctness).

## Acceptance Criteria
- [ ] Two `syncOpen` calls with identical text send exactly one didOpen and zero didChange (fake connection records calls)
- [ ] Push diagnostics from the notification stream land in the cache and reach all stream subscribers
- [ ] After `resetDocuments()`, the next `syncOpen` re-sends didOpen (not suppressed)

## Tests
- [ ] `Tests/CodeContextKitTests/LspSessionTests.swift` using `FakeLanguageServerConnection`: dedupe, versioning, cache+fanout, readiness flip on ContentModified, reset semantics
- [ ] Run `swift test --filter LspSessionTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.