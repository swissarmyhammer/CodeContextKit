---
depends_on:
- 01KWJ3TKKJPVWDQVZ2VG79RQ70
- 01KWJ3RH1RE9WJY5353AHD6JSK
position_column: todo
position_ordinal: '9380'
title: 'LspSupervisor actor: spec collection, daemon fleet, health loop'
---
## What
Create `Sources/CodeContextKit/LSP/LspSupervisor.swift` — port of `crates/swissarmyhammer-lsp/src/supervisor.rs`, minus election. On `start()`: run project detection, collect `ServerSpec`s from detected modules deduped by command, create one `LspDaemon` per unique command (all with workspace rootDirectory as rootUri), start them concurrently. Own the periodic health loop (spec.healthCheckInterval, injectable clock) calling each daemon's health check → auto-restart path. Expose `status() -> [ServerStatus]`, `forceRestart(command:)`, `shutdown()` (concurrent graceful teardown), `session(forFileExtension:)` routing an extension to its daemon's session via `Languages.all`, and `anySession()`.

## Acceptance Criteria
- [ ] Polyglot fixture (rust + two js dirs) starts exactly two daemons (rust-analyzer, typescript-language-server) — dedupe verified
- [ ] Health tick on a dead daemon triggers its restart; healthy daemons untouched
- [ ] `session(forFileExtension: "ts")` and `"tsx"` return the same session; unknown extension returns nil

## Tests
- [ ] `Tests/CodeContextKitTests/LspSupervisorTests.swift` with injected daemon/connection fakes + manual clock: dedupe, routing, health-loop restart dispatch, concurrent shutdown completes
- [ ] Run `swift test --filter LspSupervisorTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.