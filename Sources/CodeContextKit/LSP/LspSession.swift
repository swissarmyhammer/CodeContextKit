import Foundation

/// One per-uri diagnostics update, broadcast to in-process subscribers.
///
/// Carries the *latest* full set of diagnostics for `uri` — diagnostics are
/// published as a complete replacement for a document, not as a delta, so
/// each update fully describes the current state of `uri`. Ports
/// `swissarmyhammer-lsp`'s `diagnostics::DiagnosticUpdate`.
struct DiagnosticUpdate: Sendable, Equatable {
    /// The document the diagnostics apply to.
    let uri: DocumentURI

    /// The latest complete set of diagnostics for `uri`.
    let diagnostics: [Diagnostic]
}

/// What the session believes the server knows about one open document.
///
/// `version` is the LSP document version, starting at 1 on `didOpen` and
/// incremented on every text-changing `didChange`. `textHash` is a cheap
/// hash of the text last sent to the server, used so a no-op `syncOpen`
/// (identical text) does not bump the version or emit a notification. Ports
/// `swissarmyhammer-lsp`'s `session::DocState`.
struct DocState: Sendable, Equatable {
    /// The document's LSP version, as last sent to the server.
    let version: Int

    /// A hash of the text last sent to the server for this document.
    let textHash: Int
}

/// A single owned LSP session over one `LanguageServerConnection`: the
/// open-document set, the diagnostics cache and its multi-subscriber
/// fan-out, and the server's observed readiness.
///
/// Ports `swissarmyhammer-lsp`'s `session::LspSession` as a Swift actor: the
/// document-set/client mutex pair and the `tokio::sync::broadcast` channel
/// from the Rust original collapse into plain actor-isolated state plus an
/// actor-managed set of `AsyncStream` continuations (Swift's `AsyncStream`
/// only supports a single iterator per stream, so fan-out to N subscribers
/// means handing each subscriber its own stream backed by its own
/// continuation, all fed from the same `recordDiagnostics(uri:diagnostics:)`
/// write path).
///
/// On creation, the session starts consuming `connection.serverNotifications`
/// in the background so `textDocument/publishDiagnostics` pushes land in the
/// cache and fan-out without any caller having to drive a read loop.
actor LspSession<Connection: LanguageServerConnection> {
    /// The `error.code` a pull-diagnostics response carries when the server
    /// answers "still loading, retrigger later" rather than a real report
    /// (`ServerCancelled`, LSP 3.17+).
    private static var serverCancelledErrorCode: Int { -32802 }

    /// The `error.code` a pull-diagnostics response carries for the
    /// server's other "still loading" signal (`ContentModified`).
    private static var contentModifiedErrorCode: Int { -32801 }

    /// The one connection this session drives.
    private let connection: Connection

    /// The LSP `languageId` sent on every `didOpen` (e.g. `"swift"`). One
    /// session serves one server, which serves one language family.
    private let languageID: String

    /// What the server is believed to have open: `uri -> DocState`.
    private var docs: [DocumentURI: DocState] = [:]

    /// Latest-per-uri diagnostics cache: `uri -> latest full diagnostic set.
    ///
    /// Derived state — a live mirror of what the server most recently
    /// published (push) or returned (pull) for each document. Never
    /// persisted; rebuilt from server output and discarded on
    /// `resetDocuments()` or when the session is deallocated.
    private var diagnosticsCache: [DocumentURI: [Diagnostic]] = [:]

    /// Live diagnostics subscribers, keyed by an internal id so a
    /// terminated subscriber's continuation can be removed individually.
    private var diagnosticsSubscribers: [Int: AsyncStream<DiagnosticUpdate>.Continuation] = [:]

    /// The id the next `diagnosticUpdates()` subscriber will be registered
    /// under.
    private var nextSubscriberID = 0

    /// Whether the server is believed ready to report diagnostics for the
    /// workspace. See `isReady`.
    private(set) var isReady = true

    /// The background task draining `connection.serverNotifications` into
    /// the diagnostics cache and fan-out.
    ///
    /// `nonisolated(unsafe)`: assigned once from `init` (before the closure
    /// capturing `self` can run) and only ever read/cancelled from `deinit`
    /// afterward, so it is never accessed concurrently despite living
    /// outside actor isolation. It must be nonisolated because `init`
    /// creating the `Task` that captures `self` makes `self` "escape" the
    /// initializer from the compiler's point of view — after that point,
    /// only nonisolated members of `self` may be written from within `init`.
    private nonisolated(unsafe) var notificationConsumerTask: Task<Void, Never>?

    /// Creates a session over `connection`, immediately starting to consume
    /// its `serverNotifications` in the background.
    /// - Parameters:
    ///   - connection: The connection this session drives every document-sync and
    ///     diagnostics operation through.
    ///   - languageID: The LSP `languageId` to send on every `didOpen` (e.g. `"swift"`).
    init(connection: Connection, languageID: String) {
        self.connection = connection
        self.languageID = languageID
        notificationConsumerTask = Task { [weak self] in
            await self?.consumeServerNotifications()
        }
    }

    deinit {
        notificationConsumerTask?.cancel()
        for continuation in diagnosticsSubscribers.values {
            continuation.finish()
        }
    }

    /// Snapshots the current open-document set (`uri -> DocState`).
    /// - Returns: A copy of the open-document set; not a live view.
    func openDocuments() -> [DocumentURI: DocState] {
        docs
    }

    /// The number of live diagnostics subscribers, for tests to observe
    /// that a terminated subscriber's continuation is actually removed
    /// from the fan-out set rather than leaking.
    /// - Returns: How many `diagnosticUpdates()` streams are currently registered.
    func diagnosticsSubscriberCount() -> Int {
        diagnosticsSubscribers.count
    }

    /// Makes the server's buffer for `uri` match `text`, opening the
    /// document if the session has never seen it.
    ///
    /// The first sync for a uri sends `textDocument/didOpen` at version 1.
    /// A later sync for an already-open uri refreshes the buffer via
    /// `textDocument/didChange`, but only when `text` actually differs from
    /// what was last sent — an unchanged re-sync costs nothing on the wire.
    /// Because the session keeps documents open across requests, callers
    /// that depend on a document's current text (a query op, a diagnostics
    /// pull) should call this before issuing that request.
    /// - Parameters:
    ///   - uri: The document to open or refresh.
    ///   - text: The document's full current content.
    /// - Throws: Whatever `connection.didOpen`/`didChange` throws (e.g. a
    ///   transport failure).
    func syncOpen(uri: DocumentURI, text: String) async throws {
        let newHash = Self.hashText(text)
        if let state = docs[uri] {
            guard state.textHash != newHash else {
                // No textual change since the last sync — nothing to send.
                return
            }
            let nextVersion = state.version + 1
            try await connection.didChange(uri: uri, version: nextVersion, text: text)
            docs[uri] = DocState(version: nextVersion, textHash: newHash)
        } else {
            try await connection.didOpen(uri: uri, languageID: languageID, version: 1, text: text)
            docs[uri] = DocState(version: 1, textHash: newHash)
        }
    }

    /// Forgets every open document and every cached diagnostic, without
    /// sending any `didClose`.
    ///
    /// Called when the underlying server process is gone (shutdown, health
    /// check failure, or just before a restart): the new process knows
    /// nothing about what the old one had open, so the open set must be
    /// cleared to match. Sending `didClose` here would be wrong — the
    /// server the old documents were opened against no longer exists. After
    /// a reset, the next `syncOpen` for any uri emits a fresh `didOpen`
    /// instead of being suppressed as a stale duplicate. The diagnostics
    /// cache is cleared too: it is derived state describing the gone
    /// process's analysis, so it must not outlive that process.
    func resetDocuments() {
        docs.removeAll()
        diagnosticsCache.removeAll()
    }

    /// The latest captured diagnostics for a document uri.
    /// - Parameter uri: The document to look up.
    /// - Returns: A snapshot of the cached diagnostics, or an empty array if
    ///   none have been captured for `uri`.
    func diagnostics(for uri: DocumentURI) -> [Diagnostic] {
        diagnosticsCache[uri] ?? []
    }

    /// Subscribes to the in-process diagnostics fan-out.
    ///
    /// Every diagnostics batch captured after this call — whether it
    /// arrived via a push `publishDiagnostics` notification or a pull
    /// `pullDiagnostics(uri:)` request — is yielded to the returned stream.
    /// Each call returns an independent stream backed by its own
    /// continuation, so every subscriber sees every update; a subscriber
    /// that wants the state captured *before* it subscribed should read it
    /// via `diagnostics(for:)` first.
    /// - Returns: A stream of diagnostics updates, one per captured batch.
    func diagnosticUpdates() -> AsyncStream<DiagnosticUpdate> {
        let subscriberID = nextSubscriberID
        nextSubscriberID += 1
        let (stream, continuation) = AsyncStream.makeStream(of: DiagnosticUpdate.self)
        diagnosticsSubscribers[subscriberID] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeDiagnosticsSubscriber(id: subscriberID) }
        }
        return stream
    }

    /// Requests diagnostics for a document via the pull model
    /// (`textDocument/diagnostic`, LSP 3.17+) and feeds the result through
    /// the same cache and fan-out as push diagnostics.
    ///
    /// A pull issued before the server has finished loading the workspace
    /// is answered with its "still loading, retrigger later" signal
    /// (`ServerCancelled` / `ContentModified`) rather than a real report:
    /// that flips `isReady` false and returns an empty array *without*
    /// caching or broadcasting it — caching an empty body here would let a
    /// consumer misread "still loading" as "the file is clean". Any other
    /// error propagates to the caller unchanged and leaves `isReady`
    /// untouched.
    /// - Parameter uri: The document to request diagnostics for.
    /// - Returns: The document's current diagnostics, or an empty array if the
    ///   server reported it is still loading.
    /// - Throws: Whatever `connection.pullDiagnostics(for:)` throws, apart from the
    ///   "still loading" signal, which is handled rather than propagated.
    func pullDiagnostics(uri: DocumentURI) async throws -> [Diagnostic] {
        do {
            let diagnostics = try await connection.pullDiagnostics(for: uri)
            isReady = true
            recordDiagnostics(uri: uri, diagnostics: diagnostics)
            return diagnostics
        } catch let error as WireError {
            guard case let .serverError(code, _) = error, Self.isNotReadyErrorCode(code) else {
                throw error
            }
            isReady = false
            return []
        }
    }

    /// Drains `connection.serverNotifications` for the session's lifetime,
    /// feeding every `publishDiagnostics` push into the cache and fan-out.
    private func consumeServerNotifications() async {
        let notifications = await connection.serverNotifications
        for await notification in notifications {
            switch notification {
            case let .publishDiagnostics(uri, diagnostics):
                recordDiagnostics(uri: uri, diagnostics: diagnostics)
            }
        }
    }

    /// Replaces the cached diagnostics for `uri` and broadcasts the update
    /// to every live subscriber.
    ///
    /// The single write path shared by push (`consumeServerNotifications`)
    /// and pull (`pullDiagnostics(uri:)`), so the cache and the fan-out
    /// never drift apart.
    /// - Parameters:
    ///   - uri: The document the diagnostics apply to.
    ///   - diagnostics: The latest complete set of diagnostics for `uri`.
    private func recordDiagnostics(uri: DocumentURI, diagnostics: [Diagnostic]) {
        diagnosticsCache[uri] = diagnostics
        let update = DiagnosticUpdate(uri: uri, diagnostics: diagnostics)
        for continuation in diagnosticsSubscribers.values {
            continuation.yield(update)
        }
    }

    /// Removes a terminated subscriber's continuation from the fan-out set.
    /// - Parameter id: The subscriber id assigned by `diagnosticUpdates()`.
    private func removeDiagnosticsSubscriber(id: Int) {
        diagnosticsSubscribers.removeValue(forKey: id)
    }

    /// Whether a pull-diagnostics error code is the server's "still
    /// loading, retrigger later" signal rather than a genuine failure.
    /// - Parameter code: The JSON-RPC `error.code` from a pull response.
    /// - Returns: `true` for `ServerCancelled` or `ContentModified`.
    private static func isNotReadyErrorCode(_ code: Int) -> Bool {
        code == serverCancelledErrorCode || code == contentModifiedErrorCode
    }

    /// Hashes a document's text for cheap no-op-change detection.
    /// - Parameter text: The document text to hash.
    /// - Returns: A process-local hash of `text`, stable only for the lifetime of the process.
    private static func hashText(_ text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(text)
        return hasher.finalize()
    }
}
