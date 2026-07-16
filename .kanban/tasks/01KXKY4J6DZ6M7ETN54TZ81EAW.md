---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxnhv14vhvtp2hdnvsx1jqjs
  text: |-
    Implemented ServerInstaller engine per spec:
    - Sources/FoundationModelsCodeContext/LSP/ServerInstaller.swift: BinaryLookup (extracted from LSPDaemon's old private isExecutableOnPath), LspAutoInstall (public policy, isEnabled default true, timeout default 300s), InstallRunResult, InstallRunner protocol, ProcessInstallRunner (real Process spawn via /usr/bin/env, combined stdout+stderr capture with bounded tail buffer, timeout via injectable clock, prompt termination on both timeout and ambient-task cancellation via withTaskCancellationHandler, using a ResumeGuard to avoid double-resuming the completion continuation when the timeout-kill and the natural terminationHandler both race), and ServerInstaller actor (memoizes a Task<Bool,Never> per spec.command so concurrent/sequential callers dedupe to exactly one runner invocation).
    - Sources/FoundationModelsCodeContext/LSP/LSPDaemon.swift: removed the old private isExecutableOnPath, start() now calls BinaryLookup.isOnPath(spec.command).
    - Tests/FoundationModelsCodeContextTests/Support/FakeInstallRunner.swift: scripted actor fake with invocation recording, updateResult(_:), and a gate (closeGate/openGate) for concurrency tests.
    - Tests/FoundationModelsCodeContextTests/ServerInstallerTests.swift: 8 ServerInstaller cases (success, nonzero exit, throw, disabled policy, nil installer, missing tool, sequential dedupe, concurrent dedupe) + 4 ProcessInstallRunner integration cases (real exit 0 w/ combined-output capture, real exit 1, real timeout, real cancellation).

    Verification: `swift build` clean; `swift test` -> 511 tests / 44 suites all passing, including the new 12 tests and the pre-existing LSPDaemonTests exercising the extracted BinaryLookup helper. Adversarial double-check review launched to confirm no concurrency/Sendable issues before handoff.
  timestamp: 2026-07-16T13:28:44.443671+00:00
- actor: claude-code
  id: 01kxnj984kcyssa2j64ra9jd2w
  text: |-
    Adversarial double-check (via really-done) returned REVISE with 3 findings; addressed all three:
    1. Tests/FoundationModelsCodeContextTests/LiveSourceKitTests.swift's `isSourceKitLSPOnPath` had a stale doc comment referencing the now-deleted `LSPDaemon.isExecutableOnPath` and duplicated the PATH-scan logic BinaryLookup was created to centralize — replaced its body with a direct `BinaryLookup.isOnPath("sourcekit-lsp")` call and fixed the comment.
    2. Documented the accepted, narrow PID-reuse race in ProcessInstallRunner.run (the timeout task and the cancellation handler both call `kill(pid, SIGKILL)` unconditionally on a raw captured pid) — same accepted tradeoff ProcessLanguageServerConnection.close() already makes, now called out explicitly in the doc comment rather than left implicit.
    3. Tests/FoundationModelsCodeContextTests/Support/FakeInstallRunner.swift's `run()` now asserts via `precondition` if a second call arrives while already gated, so a future at-most-once regression fails loudly instead of silently hanging.

    Re-verified after fixes: `swift build` clean, `swift test` -> 511/511 tests in 44 suites passing.

    Task is green and complete: ServerInstaller actor, LspAutoInstall policy, InstallRunner/ProcessInstallRunner, and the shared BinaryLookup helper are all implemented per spec, with 12 new tests plus the fixes above. Leaving in doing for /review.
  timestamp: 2026-07-16T13:36:30.355660+00:00
depends_on:
- 01KXKY3XWKM1TRR9X0F4SQ0SF0
position_column: doing
position_ordinal: '80'
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