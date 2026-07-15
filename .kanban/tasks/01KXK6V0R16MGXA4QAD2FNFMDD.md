---
assignees:
- claude-code
depends_on:
- 01KXK6SY8JZME3N2WJM7CKSAE4
- 01KXK6T61DT9BJR17ZF798KKE4
position_column: todo
position_ordinal: '8380'
title: 'Add CodeContextManager actor: open-or-get lifecycle, routing, overlap rule'
---
## What
Create `Sources/FoundationModelsCodeContext/CodeContextManager.swift`: `public actor CodeContextManager<Connection: LanguageServerConnection>`, mirroring `CodeContext`'s visibility pattern — an internal general initializer `init(embedder:clock:eventSource:connectionFactory:)` (stores the factory/clock/eventSource used for every context it creates, so tests inject `FakeLanguageServerConnection`/`FakeFileEventSource`/`ManualClock`), plus the only public initializer in an `extension CodeContextManager where Connection == ProcessLanguageServerConnection { public init(embedder: TextEmbedding) }`.

**CodeContext stays public and unchanged** — the manager builds on it, never wraps or hides it; every accessor below hands back the real `CodeContext` instance.

State: `private var contexts: [URL: CodeContext<Connection>]` keyed by standardized root URL; `private var inFlightOpens: [URL: Task<CodeContext<Connection>, Error>]` so concurrent opens of the same root dedupe to one create+start (same pattern as `LspSupervisor.inFlightStart`); `public nonisolated let state: ManagerState`.

API (keep-all-started lifecycle — every successful open has already run `start()`):
- `public func context(for root: URL) async throws -> CodeContext<Connection>` — standardize the URL, then apply the overlap rule: exact match → return existing; `root` is a **descendant** of an open root → return that ancestor's context (its walker already covers the subtree); `root` is an **ancestor** of one or more open roots → throw the new `CodeContextError.overlappingRoot(String)` naming the conflicting children (caller must close them first). Otherwise create a `CodeContext` via the stored internal pieces, `try await start()` it (on failure: do not register; rethrow), register in `contexts`, and `await state.publishOpened(root:state:)` with the context's `state`. Accepts any directory, git repo or not — non-git workspaces are an explicit-open feature.
- `public func context(containing path: URL, openIfNeeded: Bool = true) async throws -> CodeContext<Connection>?` — longest-prefix match against open roots first (never throws on that path); else `RootDiscovery.gitRoot(containing: path)` and, if found and `openIfNeeded`, route through the throwing `context(for:)`; else nil.
- `public func close(root: URL) async` — `stop()` the context, remove it, `publishClosed`. No-op for unknown roots.
- `public func shutdown() async` — close every open context.

Descendant/ancestor checks compare standardized paths with a trailing-separator prefix test (so `/a/foo-bar` is not treated as inside `/a/foo`).

Add `case overlappingRoot(String)` to `CodeContextError` (`Sources/FoundationModelsCodeContext/CodeContextError.swift`) with an `errorDescription` entry, following the existing String-payload convention.

## Acceptance Criteria
- [ ] `context(for:)` on the same root twice returns the identical instance (`===`) and starts it once
- [ ] Concurrent `context(for:)` calls for one root create exactly one context
- [ ] Opening a descendant of an open root returns the ancestor's context; opening an ancestor of open roots throws `.overlappingRoot`
- [ ] Path-prefix check does not confuse sibling dirs sharing a name prefix
- [ ] `context(containing:)` resolves via open roots first, lazily opens via `gitRoot` when `openIfNeeded`, returns nil otherwise / outside any repo
- [ ] A failed `start()` leaves the manager unregistered for that root and the error propagates
- [ ] `close`/`shutdown` stop contexts and update `state`; `state.contexts` mirrors open roots throughout

## Tests
- [ ] `Tests/FoundationModelsCodeContextTests/CodeContextManagerTests.swift` driving the internal initializer with the existing Support fakes (`FakeLanguageServerConnection` factory, `FakeFileEventSource`, `FakeEmbedder`) over temp-dir repo fixtures, covering every acceptance criterion including the concurrent-open dedupe
- [ ] `swift test --filter CodeContextManagerTests` passes

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.