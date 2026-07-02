---
position_column: todo
position_ordinal: '80'
title: 'Package scaffold: Package.swift, deps, logging, errors'
---
## What
Create the SPM package per plan.md "Package shape". `Package.swift` (swift-tools-version 6.1, platform `.macOS("27.0")`) with dependencies: `.package(path: "../FoundationModelsRouter")`, SwiftTreeSitter (ChimeHQ), GRDB, and the first grammar packages (tree-sitter-swift, tree-sitter-rust, tree-sitter-python — more added by the language-module tasks). Create `Sources/CodeContextKit/Logging/Log.swift` (os.Logger constants: subsystem `com.swissarmyhammer.CodeContextKit`, categories lsp, lsp-wire, index, watcher, embedding, search, diagnostics) and `Sources/CodeContextKit/CodeContextError.swift` (error enum: binaryNotFound, spawnFailed, handshakeFailed, timeout, notRunning, storage, embedding cases). Empty `Tests/CodeContextKitTests/` target using Swift Testing.

## Acceptance Criteria
- [ ] `swift build` succeeds on macOS 27 with all declared dependencies resolved
- [ ] `swift test` runs (a trivial smoke test passes)
- [ ] `Log` exposes the seven category loggers; error enum is public and Sendable

## Tests
- [ ] `Tests/CodeContextKitTests/ScaffoldTests.swift`: smoke test asserting `CodeContextError` cases construct and `Log.subsystem` constant is correct
- [ ] Run `swift test` → all pass

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.