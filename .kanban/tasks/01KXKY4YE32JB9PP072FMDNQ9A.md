---
assignees:
- claude-code
depends_on:
- 01KXKY3XWKM1TRR9X0F4SQ0SF0
- 01KXKY4J6DZ6M7ETN54TZ81EAW
position_column: todo
position_ordinal: '8280'
title: Add .installing daemon state and extend binary lookup with installer search directories
---
## What
Two compiler-driven extensions to the daemon layer, in `Sources/FoundationModelsCodeContext/LSP/LSPDaemon.swift` and `Sources/FoundationModelsCodeContext/CodeContextState.swift`. (Depends on the ServerInstaller task: it extracts `isExecutableOnPath` into the shared lookup helper this task extends — do not refactor that function independently.)

1. **New `LSPDaemonState.installing` case** — "the server binary is missing and an auto-install attempt is in flight." Add:
   - an internal `LSPDaemon.noteInstalling()` transition (valid only from `.notFound`/`.notStarted`; document and guard) that the supervisor calls before kicking off an install, so the state is observable via `stateUpdates`/`ServerStatus` while the install runs. No `noteInstallFailed()` counterpart is needed: the supervisor exits `.installing` on BOTH outcomes by calling `forceRestart()`, whose re-run of `start()`'s lookup naturally lands `.running` (binary now present) or `.notFound` (still missing).
   - update **every** exhaustive switch over `LSPDaemonState` the compiler flags — most importantly `CodeContextState.isSettled`, where `.installing` is NOT settled (a workspace mid-install is not ready), matching how `.starting` is treated
   - doc-comment the Codable-schema implication on the enum: `LSPDaemonState`/`ServerStatus` are public `Codable`, and the new case changes the encoded schema — no decode site exists inside this repo, but external consumers decoding persisted `ServerStatus` values must be rebuilt against this version
2. **Installer-aware binary lookup** — the shared lookup helper (extracted by the ServerInstaller task) must also honor `spec.installer?.extraSearchDirectories` (with `~` expansion), because native global installs from `go install`/`rustup` land in `~/go/bin`/`~/.cargo/bin`, which are often not on `$PATH`:
   - search `$PATH` first, then the extra directories
   - **absolute-path spawn mechanism**: `ConnectionFactory` is `(ServerSpec, URL) → ConnectionHandle` and the production factory spawns `spec.command` — there is no separate command parameter. When the binary resolves only via an extra directory, hand the factory a **rebuilt `ServerSpec` copy** whose `command` is the absolute path (full memberwise init, including the new `installer` field). The daemon's own stored `spec` / `command()` MUST remain the bare name — it is the supervisor's dedupe and session-routing key and `ServerStatus.command`.

## Acceptance Criteria
- [ ] `.installing` is observable through `ServerStatus`, and `CodeContextState.isReady` is false while any daemon is installing
- [ ] `noteInstalling()` from `.running` or `.shuttingDown` is rejected (no-op or assertion, per the guard chosen)
- [ ] A binary present only in an `extraSearchDirectories` dir (not `$PATH`) is found and spawned via a spec copy carrying the absolute path, while the daemon's `command()`/`ServerStatus.command` still reports the bare name
- [ ] A binary on neither `$PATH` nor extra dirs still lands in `.notFound` with the existing hint warning

## Tests
- [ ] Extend `Tests/FoundationModelsCodeContextTests` daemon/state tests: `.installing` settledness in `CodeContextState` (isReady false mid-install), `noteInstalling()` transition guards, and lookup tests using a temp directory as `extraSearchDirectories` containing a fake executable (chmod +x) — assert resolution, the absolute-path spec copy received by the fake connection factory, the bare-name `command()`, and the still-notFound case
- [ ] `swift test` passes (the exhaustive-switch updates keep everything compiling)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.