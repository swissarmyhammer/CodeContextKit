import Darwin
import Foundation

/// Searches `$PATH` for an executable, mirroring how a shell resolves a bare command name to a
/// binary.
///
/// Extracted from `LSPDaemon` (which uses it to gate spawning a language-server binary,
/// surfacing a distinct `.notFound` state before ever spawning) so `ServerInstaller` can reuse
/// the exact same lookup to gate whether an installer's own `tool` (e.g. `"npm"`, `"rustup"`) is
/// available before attempting to run it. `ProcessLanguageServerConnection` also spawns via a
/// `$PATH` lookup (through `/usr/bin/env`), but that lookup surfaces as a generic spawn failure
/// rather than the distinct up-front check both callers of this helper need.
enum BinaryLookup {
    /// Reports whether `command` resolves to an executable file somewhere on `$PATH`.
    /// - Parameter command: The executable name to search for (no path separators).
    /// - Returns: `true` if `command` resolves to an executable file on `$PATH`; `false` otherwise.
    static func isOnPath(_ command: String) -> Bool {
        guard let pathVariable = ProcessInfo.processInfo.environment["PATH"] else { return false }
        let searchDirectories = pathVariable.split(separator: ":").map(String.init)
        for directory in searchDirectories {
            let candidatePath = (directory as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidatePath) {
                return true
            }
        }
        return false
    }
}

/// The opt-out policy governing whether `ServerInstaller` may run a language server's
/// machine-actionable installer (`ServerSpec.installer`) automatically.
///
/// On by default. When a spec carries an `InstallSpec`, running its installer means running the
/// ecosystem's *native global installer* directly on the user's machine — `npm install -g`,
/// `rustup component add`, `go install`, `pipx install`, or `brew install`, exactly the commands
/// captured on each `ServerSpec.InstallSpec` (see `Languages/ServerSpec.swift`). That is a real,
/// user-visible side effect: it writes into the user's global npm/cargo/go/pipx/brew state, the
/// same as if the user had typed the command themselves. Set `isEnabled` to `false` to opt out
/// and fall back to `installHint`-only guidance — exactly the behavior before auto-install
/// existed, and always the behavior for a spec whose `installer` is `nil`.
public struct LspAutoInstall: Sendable, Equatable {
    /// Whether `ServerInstaller` may run a spec's installer automatically. Defaults to `true`.
    public var isEnabled: Bool

    /// How long one install command may run before it is treated as failed and force-terminated.
    /// Defaults to 300 seconds — generous enough for a cold `npm install -g` or `go install` on a
    /// slow connection, but still bounded.
    public var timeout: Duration

    /// Creates an auto-install policy.
    /// - Parameters:
    ///   - isEnabled: Whether auto-install is permitted. Defaults to `true`.
    ///   - timeout: How long one install command may run before it is force-terminated as failed.
    ///     Defaults to 300 seconds.
    public init(isEnabled: Bool = true, timeout: Duration = .seconds(300)) {
        self.isEnabled = isEnabled
        self.timeout = timeout
    }
}

/// The outcome of one `InstallRunner.run(tool:arguments:timeout:)` call that completed (as
/// opposed to throwing).
struct InstallRunResult: Sendable, Equatable {
    /// The installer process's exit code. `0` conventionally means success.
    let exitCode: Int32

    /// A bounded tail of the installer's combined stdout+stderr output, for error reporting when
    /// `exitCode != 0`.
    let output: String
}

/// The process-running seam `ServerInstaller` drives, mirroring how `ConnectionFactory` decouples
/// `LSPDaemon` from real processes: production code runs a real installer via
/// `ProcessInstallRunner`, unit tests substitute a scripted `FakeInstallRunner` and never spawn
/// anything.
protocol InstallRunner: Sendable {
    /// Runs `tool` with `arguments`, bounded by `timeout`.
    /// - Parameters:
    ///   - tool: The installer executable to run, looked up on `$PATH`.
    ///   - arguments: The full argv tail passed to `tool`.
    ///   - timeout: How long to wait before force-terminating `tool` and throwing
    ///     `CodeContextError.timeout`.
    /// - Returns: The completed run's exit code and a bounded output tail.
    /// - Throws: `CodeContextError.spawnFailed` if `tool` could not be launched;
    ///   `CodeContextError.timeout` if `timeout` elapses before `tool` exits.
    func run(tool: String, arguments: [String], timeout: Duration) async throws -> InstallRunResult
}

/// Thread-safe bounded tail of a process's combined stdout+stderr output.
///
/// Mirrors `ProcessLanguageServerConnection`'s `StderrTailBuffer`: an install command can produce
/// substantial output (a verbose `npm install -g` or `go install` run), so only the most recent
/// chunks are retained, bounding memory while still giving `ServerInstaller`'s failure log enough
/// context to diagnose why an install failed. `@unchecked Sendable` is safe because every access
/// goes through `lock`.
private final class InstallOutputTailBuffer: @unchecked Sendable {
    /// The number of most-recent chunks retained; older chunks are dropped.
    private static let maxChunks = 40

    private let lock = NSLock()
    private var chunks: [String] = []

    /// Appends one output chunk, evicting the oldest chunk if the buffer is now over capacity.
    /// - Parameter chunk: The raw text read from the process's combined stdout/stderr pipe.
    func append(chunk: String) {
        lock.lock()
        defer { lock.unlock() }
        chunks.append(chunk)
        if chunks.count > Self.maxChunks {
            chunks.removeFirst(chunks.count - Self.maxChunks)
        }
    }

    /// A snapshot of every retained chunk, oldest first.
    /// - Returns: The retained output chunks joined together, or an empty string if none have
    ///   been captured yet.
    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return chunks.joined()
    }
}

/// Resumes a single `CheckedContinuation` at most once.
///
/// `ProcessInstallRunner.run` races two independent completion sources against the same
/// continuation — the process exiting on its own (`Process.terminationHandler`) and the injected
/// clock's timeout firing first (which force-kills the process, so the terminationHandler still
/// fires afterward) — exactly the kind of race `PendingRequestTable.resolve(id:with:)` guards
/// against for JSON-RPC responses vs. request timeouts. This is the same idempotent-resume
/// guarantee, specialized to a single continuation instead of a table keyed by request id.
/// `@unchecked Sendable` is safe because every access goes through `lock`.
private final class ResumeGuard<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<Value, Error>

    /// Creates a guard wrapping `continuation`.
    /// - Parameter continuation: The continuation to resume at most once.
    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    /// Resumes the wrapped continuation with `value`, unless it has already been resumed.
    /// - Parameter value: The value to resume with.
    func resume(returning value: Value) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        continuation.resume(returning: value)
    }

    /// Resumes the wrapped continuation by throwing `error`, unless it has already been resumed.
    /// - Parameter error: The error to resume with.
    func resume(throwing error: Error) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        lock.unlock()
        continuation.resume(throwing: error)
    }
}

/// The production `InstallRunner`: spawns `tool` as a real child process via Foundation
/// `Process`.
///
/// Spawns via `/usr/bin/env <tool> <args>`, matching `ProcessLanguageServerConnection`'s
/// `$PATH`-resolution approach. Terminates the child in both of its exit paths: a `timeout` that
/// elapses before the process exits kills it and throws `CodeContextError.timeout`, and the
/// *calling* task being cancelled (e.g. a production `shutdown()` racing a real `brew`/`npm` run)
/// kills it via `withTaskCancellationHandler` — without this, a caller wanting to shut down
/// promptly would otherwise have to wait out up to the full `timeout` before the child is reaped.
struct ProcessInstallRunner: InstallRunner {
    /// The clock the per-run timeout sleeps against. Defaults to `ContinuousClock()`; tests that
    /// need to control the timeout without waiting in real time inject a `ManualClock` — though
    /// the integration tests in `ServerInstallerTests.swift` mostly prefer real, short timeouts
    /// against real short-lived executables instead, since exercising a real `Process` spawn/kill
    /// end-to-end is the point of those cases.
    private let clock: any Clock<Duration>

    /// Creates a process-backed install runner.
    /// - Parameter clock: The clock the per-run timeout sleeps against. Defaults to
    ///   `ContinuousClock()`.
    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func run(tool: String, arguments: [String], timeout: Duration) async throws -> InstallRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            throw CodeContextError.spawnFailed("\(tool): \(error.localizedDescription)")
        }

        // Captured as a raw pid rather than closing over `process` itself in the concurrent
        // closures below: `Process` is not `Sendable`, so every closure that can run concurrently
        // with `run`'s own execution (the timeout task, the cancellation handler) only ever
        // touches this `Int32` and never the process object, mirroring how
        // `ProcessLanguageServerConnection`'s background loops capture a raw file descriptor
        // rather than the `FileHandle`/`Process` itself. This does leave an accepted, narrow
        // residual risk: `timeoutTask` and `onCancel` below both call `kill(pid, SIGKILL)`
        // unconditionally, so if the process has already exited and the OS has recycled `pid` for
        // an unrelated process in the brief window before either call runs, that unrelated process
        // could be signaled instead. `ProcessLanguageServerConnection.close()` accepts the same
        // unconditional-`kill`-by-pid risk already; both call sites judge the window (a handful of
        // scheduler ticks between exit and the next `kill` call) an acceptable tradeoff against the
        // complexity of a synchronized "already exited" flag.
        let pid = process.processIdentifier

        let tailBuffer = InstallOutputTailBuffer()
        let outputFileDescriptor = outputPipe.fileHandleForReading.fileDescriptor
        let drainTask = Task.detached {
            Self.drainOutput(fileDescriptor: outputFileDescriptor, into: tailBuffer)
        }

        let installClock = clock

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<InstallRunResult, Error>) in
                let resumeGuard = ResumeGuard(continuation: continuation)

                let timeoutTask = Task {
                    do {
                        try await installClock.sleep(for: timeout)
                    } catch {
                        // Cancelled below once the process exits on its own first.
                        return
                    }
                    kill(pid, SIGKILL)
                    resumeGuard.resume(throwing: CodeContextError.timeout(timeout))
                }

                process.terminationHandler = { finished in
                    timeoutTask.cancel()
                    let exitCode = finished.terminationStatus
                    Task {
                        await drainTask.value
                        resumeGuard.resume(returning: InstallRunResult(exitCode: exitCode, output: tailBuffer.snapshot()))
                    }
                }
            }
        } onCancel: {
            // Kills promptly on cancellation independent of the continuation/timeout race above:
            // `pid` is already known by this point (the process is spawned before this handler is
            // installed), so this never has to coordinate with `resumeGuard` — the process dying
            // here still resolves the continuation normally, through `terminationHandler` above.
            kill(pid, SIGKILL)
        }
    }

    /// Reads `fileDescriptor` until EOF, appending every chunk read to `tailBuffer`.
    ///
    /// Runs detached, outside any actor isolation, mirroring
    /// `ProcessLanguageServerConnection.runStderrDrainLoop`: a single raw `read(2)` call per
    /// iteration returns as soon as any data is available, and an `EINTR` (a read interrupted by
    /// a signal — frequent when other child processes are also being spawned/reaped concurrently)
    /// is retried rather than treated as EOF.
    /// - Parameters:
    ///   - fileDescriptor: The pipe read end's raw file descriptor.
    ///   - tailBuffer: The bounded tail buffer to append every read chunk to.
    private static func drainOutput(fileDescriptor: Int32, into tailBuffer: InstallOutputTailBuffer) {
        let chunkSize = 65536
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            errno = 0
            let bytesRead = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return read(fileDescriptor, baseAddress, chunkSize)
            }
            if bytesRead > 0 {
                if let text = String(data: Data(buffer[0..<bytesRead]), encoding: .utf8) {
                    tailBuffer.append(chunk: text)
                }
                continue
            }
            if bytesRead < 0, errno == EINTR {
                continue
            }
            return
        }
    }
}

/// Orchestrates running a language server's machine-actionable installer, subject to the
/// `LspAutoInstall` opt-out policy.
///
/// Per plan.md's LSP subsystem design, this is the auto-install counterpart to `LSPDaemon`: where
/// `LSPDaemon` spawns and monitors a language server itself, `ServerInstaller` spawns the
/// *installer* that puts that server on `$PATH` in the first place, before the daemon ever tries
/// to start it. An actor so every attempted command is tracked without a lock: `install(spec:)`
/// records attempted commands and never retries a completed or in-flight attempt — the backstop
/// against install loops (e.g. an install that "succeeds" per its exit code but doesn't actually
/// leave the binary discoverable, which would otherwise retry forever every time the daemon
/// re-checks `$PATH`). Concurrent callers asking to install the same command all await the same
/// in-flight `Task`, so the underlying installer runs exactly once no matter how many callers ask
/// concurrently.
///
/// Note the cancellation semantics of that shared in-flight `Task`: a caller whose own await of
/// `install(spec:)` is cancelled does *not* cancel the underlying install — the `Task` backing an
/// in-flight attempt is intentionally unstructured (not a structured child of any one caller), so
/// it keeps running to completion for whichever other callers are also awaiting it. It is
/// `ProcessInstallRunner`'s own cancellation handling (see its doc comment) that makes a genuine
/// shutdown of the *runner's* task prompt, not anything `install(spec:)` does with the caller's
/// cancellation here.
actor ServerInstaller {
    /// The opt-out policy gating whether `install(spec:)` may ever invoke `runner`.
    private let policy: LspAutoInstall

    /// The process-running seam. Production code uses the default `ProcessInstallRunner()`; tests
    /// inject a scripted `FakeInstallRunner`.
    private let runner: any InstallRunner

    /// Every attempted install, keyed by `ServerSpec.command`, recording whether the install
    /// succeeded once the runner call completes. Never cleared: a command that reaches this
    /// dictionary — successfully or not — is never retried by this instance again.
    private var attempts: [String: Task<Bool, Never>] = [:]

    /// Creates a server installer.
    /// - Parameters:
    ///   - policy: The opt-out policy gating auto-install. Defaults to `LspAutoInstall()`
    ///     (enabled, 300-second timeout).
    ///   - runner: The process-running seam. Defaults to `ProcessInstallRunner()`.
    init(policy: LspAutoInstall = LspAutoInstall(), runner: any InstallRunner = ProcessInstallRunner()) {
        self.policy = policy
        self.runner = runner
    }

    /// Attempts to install `spec.command` via its `installer`, subject to the auto-install policy.
    ///
    /// Returns `false` immediately — without ever invoking `runner` — when `spec.installer` is
    /// `nil`, when the policy is disabled, or when the installer's own `tool` isn't on `$PATH`
    /// (checked via `BinaryLookup`, the same lookup `LSPDaemon` uses for `spec.command` itself).
    /// Otherwise runs `runner.run(tool:arguments:timeout:)` at most once for this command: a
    /// second call (concurrent or sequential) for the same `spec.command` awaits the first
    /// attempt's already-in-flight or already-completed `Task` instead of running the installer
    /// again.
    /// - Parameter spec: The server spec whose `installer` (if any) to run.
    /// - Returns: `true` if the installer command exited `0`; `false` for a disabled policy, a
    ///   nil/unrunnable installer, a nonzero exit, or a runner throw/timeout.
    func install(spec: ServerSpec) async -> Bool {
        guard policy.isEnabled else { return false }
        guard let installer = spec.installer else { return false }
        guard BinaryLookup.isOnPath(installer.tool) else { return false }

        if let inFlightOrCompleted = attempts[spec.command] {
            return await inFlightOrCompleted.value
        }

        let runner = self.runner
        let timeout = policy.timeout
        let task = Task<Bool, Never> {
            await Self.performInstall(runner: runner, command: spec.command, installer: installer, timeout: timeout)
        }
        attempts[spec.command] = task
        return await task.value
    }

    /// Runs one installer command to completion, logging start/success/failure via `Log.lsp`.
    /// - Parameters:
    ///   - runner: The process-running seam to invoke.
    ///   - command: The server command being installed, for logging.
    ///   - installer: The installer to run.
    ///   - timeout: How long the installer may run before it is force-terminated as failed.
    /// - Returns: `true` if the installer exited `0`; `false` for a nonzero exit or a runner
    ///   throw/timeout.
    private static func performInstall(
        runner: any InstallRunner,
        command: String,
        installer: ServerSpec.InstallSpec,
        timeout: Duration
    ) async -> Bool {
        Log.lsp.info(
            "installing \(command, privacy: .public) via \(installer.tool, privacy: .public) \(installer.arguments.joined(separator: " "), privacy: .public)"
        )
        do {
            let result = try await runner.run(tool: installer.tool, arguments: installer.arguments, timeout: timeout)
            guard result.exitCode == 0 else {
                Log.lsp.error(
                    "install failed for \(command, privacy: .public) (exit \(result.exitCode)): \(result.output, privacy: .public)"
                )
                return false
            }
            Log.lsp.info("installed \(command, privacy: .public) successfully via \(installer.tool, privacy: .public)")
            return true
        } catch {
            Log.lsp.error("install errored for \(command, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
