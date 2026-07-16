import Foundation

@testable import FoundationModelsCodeContext

/// A scripted `InstallRunner` for `ServerInstallerTests`: records every invocation and returns a
/// pre-configured result (or throws a pre-configured error) without ever touching a real process.
///
/// An actor, like `FakeLanguageServerConnection`, so concurrent callers (the concurrent-dedupe
/// tests deliberately call `ServerInstaller.install(spec:)` from more than one task at once)
/// never race on `invocations`.
actor FakeInstallRunner: InstallRunner {
    /// One recorded `run(tool:arguments:timeout:)` invocation.
    struct Invocation: Equatable {
        let tool: String
        let arguments: [String]
        let timeout: Duration
    }

    /// Every invocation recorded so far, in call order.
    private(set) var invocations: [Invocation] = []

    /// The result the next (and every subsequent) call returns, unless it throws instead. Defaults
    /// to a successful exit `0` with no output.
    private var result: Result<InstallRunResult, Error> = .success(InstallRunResult(exitCode: 0, output: ""))

    /// Replaces the scripted result every subsequent `run` call returns (or throws).
    /// - Parameter newResult: The result to script.
    func updateResult(_ newResult: Result<InstallRunResult, Error>) {
        result = newResult
    }

    /// A continuation a call suspends on while `isGated` is `true`, released by `openGate()`.
    private var gateContinuation: CheckedContinuation<Void, Never>?

    /// Whether the next call should suspend until `openGate()` is called, letting a test hold an
    /// install "in flight" to assert the at-most-once/concurrent-dedupe behavior before letting it
    /// complete.
    private var isGated = false

    /// Configures every subsequent call to suspend until `openGate()` is called.
    func closeGate() {
        isGated = true
    }

    /// Releases every call currently suspended by `closeGate()`, and stops gating future calls.
    func openGate() {
        isGated = false
        gateContinuation?.resume()
        gateContinuation = nil
    }

    func run(tool: String, arguments: [String], timeout: Duration) async throws -> InstallRunResult {
        invocations.append(Invocation(tool: tool, arguments: arguments, timeout: timeout))
        if isGated {
            // A second concurrent call arriving here while the first is still gated would mean
            // `ServerInstaller.install(spec:)`'s at-most-once dedupe regressed — assert loudly
            // rather than silently overwriting `gateContinuation` and leaving the first caller
            // suspended forever (which would otherwise surface only as an unrelated test timeout).
            precondition(
                gateContinuation == nil,
                "FakeInstallRunner.run() invoked concurrently while already gated — ServerInstaller's at-most-once dedupe likely regressed"
            )
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                gateContinuation = continuation
            }
        }
        return try result.get()
    }
}
