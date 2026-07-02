---
depends_on:
- 01KWJ3S972X06D1TKBDBCVB3SD
position_column: todo
position_ordinal: 8f80
title: 'LspDaemon actor: state machine, handshake, health, backoff auto-restart'
---
## What
Create `Sources/CodeContextKit/LSP/LspDaemon.swift` — port of `crates/swissarmyhammer-lsp/src/daemon.rs` as an actor owning one child process + its connection + session. State machine `notStarted → starting → running(pid) → failed(reason, attempts) → shuttingDown`, observable via AsyncStream. Lifecycle per plan.md: PATH lookup (miss → .notFound + installHint logged once); spawn; initialize (rootUri, empty capabilities) + initialized bounded by spec.startupTimeout, capturing a stderr tail into handshake errors; health check = process-exit detection; on unexpected exit log .error with status, tear down connection, `session.resetDocuments()`, → .failed, restart with backoff 1,2,4,8,16,32,60s cap, give up after 5 consecutive failures; success resets counter; `forceRestart()` resets counter; graceful shutdown (shutdown req → exit notif → wait, 5s grace, then kill). Connection factory + clock injected so tests never spawn real servers.

## Acceptance Criteria
- [ ] Induced crash (fake connection dies) triggers restart with correct backoff sequence and a resetDocuments call between attempts (manual test clock)
- [ ] Sixth consecutive failure leaves state .failed permanently until forceRestart
- [ ] Graceful shutdown sends shutdown+exit and reaches .notStarted within the grace bound

## Tests
- [ ] `Tests/CodeContextKitTests/LspDaemonTests.swift` with injected fake connection factory + manual clock: full lifecycle, backoff sequence values, give-up-at-5, forceRestart reset, handshake-timeout → kill path
- [ ] Run `swift test --filter LspDaemonTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.