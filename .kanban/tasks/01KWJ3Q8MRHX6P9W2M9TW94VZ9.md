---
depends_on:
- 01KWJ3P3GAY5KVH271AZNAS8D1
position_column: todo
position_ordinal: '8480'
title: LSP wire codec and typed message payloads (private JSON-RPC)
---
## What
Create `Sources/CodeContextKit/LSP/Wire.swift` + `LSPTypes.swift`. The **internal** (non-public) wire codec: Content-Length framing encode/decode over Data, JSON-RPC request/response/notification envelopes with id matching. Hand-written `Codable` structs for exactly the payloads we use (~17 methods): initialize/initialized, didOpen/didChange/didSave/didClose, documentSymbol (both `DocumentSymbol[]` nested and legacy `SymbolInformation[]` shapes), definition/typeDefinition/hover/references/implementation, prepareCallHierarchy + incoming/outgoingCalls, prepareRename/rename, codeAction + resolve, workspace/symbol, textDocument/diagnostic (pull), publishDiagnostics (push), shutdown/exit. Shared types: `DocumentURI`, `Position`, `Range`, `Location`, `Diagnostic`, `DiagnosticSeverity`, `CallHierarchyItem`. Lenient diagnostic parsing (malformed items skipped, severity defaults to hint) per Rust `diagnostics.rs`.

## Acceptance Criteria
- [ ] Framing round-trips messages incl. multi-byte UTF-8 and split reads (partial buffer feeds)
- [ ] documentSymbol decoder handles both nested and flat legacy shapes
- [ ] Nothing in this file is `public` except the shared LSP value types (Position, Location, Diagnostic, …)

## Tests
- [ ] `Tests/CodeContextKitTests/WireTests.swift`: framing round-trip incl. chunked input; payload decode fixtures captured from real server transcripts (rust-analyzer, sourcekit-lsp JSON samples embedded as strings); lenient diagnostics parsing
- [ ] Run `swift test --filter WireTests` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.