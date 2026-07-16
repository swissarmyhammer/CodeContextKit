---
assignees:
- claude-code
depends_on:
- 01KXKY3XWKM1TRR9X0F4SQ0SF0
position_column: todo
position_ordinal: '8180'
title: Add ServerInstaller engine with injectable process runner and LspAutoInstall policy
---
## What
Create `Sources/FoundationModelsCodeContext/LSP/ServerInstaller.swift`:

- `public struct LspAutoInstall: Sendable` — the opt-out policy: `isEnabled: Bool = true` (on by default, per agreed design), `timeout: Duration = .seconds(300)`. Doc-comment that installs run the ecosystem's native global installer (npm -g, rustup component, go install, pipx, brew) on the user's machine and how to opt out.
- **Extract `LSPDaemon.isExecutableOnPath` into a shared internal helper** (e.g. `BinaryLookup` in this file or a small sibling) that both `LSPDaemon` and `ServerInstaller` consume — the downstream task extending lookup with `extraSearchDirectories` builds on this same helper, so this extraction must land here first (task 3 depends on this task for exactly this reason).
- `protocol InstallRunner: Sendable` — the test seam, mirroring how `ConnectionFactory` decouples `LSPDaemon` from real processes: `func run(tool: String, arguments: [String], timeout: Duration) async throws -> InstallRunResult` where `InstallRunResult` carries `exitCode: Int32` and a bounded `output: String` tail (stdout+stderr combined) for error reporting.
- `struct ProcessInstallRunner: InstallRunner` — production implementation on Foundation `Process` (spawn via `/usr/bin/env <tool> <args>`, matching `ProcessLanguageServerConnection`'s PATH-resolution approach). Must terminate the child in BOTH exit paths: kills on timeout throwing `CodeContextError.timeout`, AND kills on **task cancellation** via `withTaskCancellationHandler` — a production `shutdown()` during a real brew/npm run must not block for up to the 300 s timeout.
- `actor ServerInstaller` — orchestrates: `func install(spec: ServerSpec) async -> Bool` (true = install command succeeded):
  - returns false immediately when `spec.installer == nil`, when the policy is disabled, or when the installer `tool` isn't on `$PATH` (via the shared lookup helper)
  - **at-most-once per `spec.command` per instance** — records attempted commands and never retries a completed or in-flight attempt (concurrent callers for the same command await the same in-flight result); this is the backstop against install loops. Note the cancellation semantics of the shared in-flight `Task`: a caller awaiting a shared task's value being cancelled does not cancel the underlying install — the runner-level cancellation handler above is what makes shutdown prompt.
  - logs start/success/failure with the captured output tail via `Log.lsp`

## Acceptance Criteria
- [ ] Disabled policy, nil installer, or missing installer tool → no runner invocation, returns false
- [ ] Exit 0 → true; nonzero exit → false with output tail logged; runner throw/timeout → false
- [ ] Same command installed twice (sequentially or concurrently) invokes the runner exactly once
- [ ] `ProcessInstallRunner` enforces its timeout AND terminates its child promptly when the running task is cancelled
- [ ] `isExecutableOnPath` logic lives in one shared helper consumed by both `LSPDaemon` and `ServerInstaller`

## Tests
- [ ] `Tests/FoundationModelsCodeContextTests/ServerInstallerTests.swift` with a `FakeInstallRunner` (in Tests Support/, alongside the existing fakes): success, nonzero-exit, throwing runner, policy-disabled, nil-installer, tool-missing, and at-most-once/concurrent-dedupe cases
- [ ] `ProcessInstallRunner` integration cases using harmless real executables — `true` (exit 0), `false` (exit 1), `sleep 60` with a sub-second timeout asserting `CodeContextError.timeout`, and `sleep 60` cancelled mid-run asserting prompt return (bounded wall-clock) — no network, CI-safe
- [ ] `swift test --filter ServerInstallerTests` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.