---
assignees:
- claude-code
depends_on:
- 01KXKY4J6DZ6M7ETN54TZ81EAW
- 01KXKY4YE32JB9PP072FMDNQ9A
position_column: todo
position_ordinal: '8380'
title: Wire auto-install into LspSupervisor and plumb LspAutoInstall through CodeContext and CodeContextManager
---
## What
The detection → install → retry flow, in `Sources/FoundationModelsCodeContext/LSP/LspSupervisor.swift`, `CodeContext.swift`, and `CodeContextManager.swift`:

- `LspSupervisor` gains an `autoInstall: LspAutoInstall` init parameter (default `.init()`) and one owned `ServerInstaller`. After a spawn round (`spawnDaemons(for:)` / `performStart()`), for each daemon that landed in `.notFound` with `spec.installer != nil` and the policy enabled:
  1. call `daemon.noteInstalling()` **synchronously in the spawn round, BEFORE spawning the background task** — `CodeContext.start()` publishes server status immediately after `supervisor.start()` returns, and a daemon still reading `.notFound` in that window is classified settled, so `isReady` would flicker true→false. Marking installing first means `start()` returns with the state already unsettled.
  2. spawn an **owned background install task** (like the per-daemon health-check tasks — installs can take minutes and must NOT block `start()`): `await installer.install(spec:)`
  3. then, on **BOTH success and failure**, guard `!Task.isCancelled` (mirroring the documented guard in `startHealthLoop`) and `try? await daemon.forceRestart()` — this is the single mechanism that exits `.installing`: the restarted lookup (which now covers `extraSearchDirectories`) lands `.running` when the install delivered the binary, or re-lands `.notFound` when it didn't. `ServerInstaller`'s at-most-once guard is what prevents a re-`.notFound` daemon from ever triggering a second install. Without this both-paths restart, a failed install would strand the daemon in `.installing` and `isReady` would never become true.
  - Install tasks are tracked alongside health tasks and cancelled+awaited in `shutdown()`; prompt shutdown is guaranteed by `ProcessInstallRunner`'s cancellation handler (see the ServerInstaller task) plus the `Task.isCancelled` guard before `forceRestart()`.
- `CodeContext`: both initializers gain `autoInstall: LspAutoInstall = LspAutoInstall()` and pass it to the supervisor. Existing callers compile unchanged (defaulted parameter).
- `CodeContextManager`: both initializers gain the same defaulted parameter and forward it to every `CodeContext` they create.
- `CodeContextState.isReady` needs no new logic — `.installing` is already not-settled from the prior task.

## Acceptance Criteria
- [ ] A `.notFound` daemon with an installer and enabled policy transitions `.notFound → .installing → .running` when the (fake) install succeeds and the binary then resolves
- [ ] Install failure transitions `.installing → .notFound` via the same both-paths `forceRestart()`; no retry loop (installer invoked at most once per command)
- [ ] `supervisor.start()` returns with affected daemons already reporting `.installing` (no settled-`.notFound` flicker window), and without waiting for installs
- [ ] Policy disabled or `installer == nil` → no install task, daemon stays `.notFound` (today's behavior, verified by absence of runner invocations)
- [ ] `shutdown()` during an in-flight install cancels cleanly and promptly (no leaked task, no post-shutdown state transitions, bounded wall-clock)
- [ ] `autoInstall` reaches the supervisor from both `CodeContext` and `CodeContextManager` inits; all existing call sites compile unchanged

## Tests
- [ ] Extend `Tests/FoundationModelsCodeContextTests` supervisor tests using `FakeInstallRunner` + `FakeLanguageServerConnection`: full success path (assert the observable state sequence via `stateUpdates`/`status()`; the fake runner's success closure must materialize a chmod+x fake executable in the spec's temp `extraSearchDirectories` dir so the post-install lookup genuinely resolves — same technique as the daemon lookup tests), failure path (`.installing → .notFound`, runner called once), disabled-policy path, nil-installer path, non-blocking `start()` returning while install is pending with state already `.installing`, and shutdown-during-install
- [ ] A `CodeContext`-level test asserting `state.isReady` is false from the moment `start()` returns through a pending fake install and becomes true after it resolves
- [ ] `swift test` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.