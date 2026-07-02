---
depends_on:
- 01KWJ3Q8MRHX6P9W2M9TW94VZ9
position_column: todo
position_ordinal: '8780'
title: LanguageServerConnection protocol, process-backed impl, in-memory fake
---
## What
Create `Sources/CodeContextKit/LSP/LanguageServerConnection.swift` — the typed seam per plan.md: one async method per LSP capability (documentSymbols, definition, typeDefinition, hover, references, implementations, prepareCallHierarchy, outgoingCalls, incomingCalls, prepareRename, rename, codeActions, resolveCodeAction, workspaceSymbols, pullDiagnostics, didOpen/didChange/didSave/didClose, initialize/initialized, shutdown/exit) plus `serverNotifications: AsyncStream<ServerNotification>`. `ProcessLanguageServerConnection.swift`: Foundation.Process + Pipe, reader loop feeding the wire codec, id-matched pending-request table, 30s per-request timeout, stderr drained to `Log.lsp` at .debug, `close()` tears down pipes. `Tests/.../Support/FakeLanguageServerConnection.swift`: scripted typed responses, induced errors/crashes, call recording — conforms to the same protocol, never touches JSON.

## Acceptance Criteria
- [ ] No method string, id, or raw JSON appears in the protocol or any public signature
- [ ] Concurrent requests interleave correctly (out-of-order responses matched by id)
- [ ] A request that never gets a response fails with timeout after 30s (injectable clock for the test)

## Tests
- [ ] `Tests/CodeContextKitTests/ConnectionTests.swift`: drive `ProcessLanguageServerConnection` against a scripted subprocess (tiny stdin/stdout echo script emitting canned JSON-RPC) for request/response, out-of-order ids, server-initiated publishDiagnostics surfacing on the stream, timeout path
- [ ] Run `swift test --filter ConnectionTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.