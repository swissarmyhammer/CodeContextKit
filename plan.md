# CodeContextKit — Port Plan

Port the code-context and LSP capabilities from `../swissarmyhammer` (Rust) to a
Swift package, **CodeContextKit**, used strictly **in-process**. One process, one
workspace, one owner of the index and the LSP servers.

## Goal

```swift
let context = try await CodeContext(rootDirectory: URL(filePath: "/path/to/repo"),
                                    embedder: someEmbedder)   // injected, see Embeddings
try await context.start()          // walk, reconcile, index, watch, spawn LSP

let hits    = try await context.searchSymbol("parse_config")
let graph   = try await context.callGraph(of: "handleRequest", direction: .inbound)
let radius  = try await context.blastRadius(file: "Sources/App/Server.swift")
let results = try await context.searchCode("retry with backoff", topK: 20)
let diags   = try await context.diagnostics(scope: .workingTree)

// SwiftUI harness binds to unified in-memory state (servers, progress, diagnostics)
struct StatusView: View {
    let state: CodeContextState        // @Observable, published by the kit
    var body: some View { ForEach(state.servers) { ... } }
}
```

This package is the engine only — no server of any kind, no MCP, no CLI. The
consumer is a **higher-level package that wraps these ops as FoundationModels
`Tool` implementations** for an in-process agent harness. Two design
consequences here:

- Every op result is a plain `Codable & Sendable` value type, so a `Tool`
  wrapper is a thin `call(arguments:) -> output` shim over one async method —
  no adaptation layer needed.
- `CodeContext` is cheap to hold alongside the agent's other tools and safe
  to call concurrently from tool invocations (actor-isolated where it
  matters, read-only queries in parallel).

## What we are NOT porting (simplifications)

| Rust subsystem | Why it's dropped |
|---|---|
| `swissarmyhammer-leader-election` (flock election, lease/heartbeat, unix-socket IPC, ZMQ bus) | Single process owns everything |
| Leader/Follower `WorkspaceMode`, `FollowerGuard`, `step_down`, `open_as_follower` | Same |
| `LiveLspRouter` / `MultiLspRouter` follower→leader routing seams | Ops talk to the in-process `LspSession` directly |
| `spawn_reelection_loop`, follower diagnostics subscriber, promotion gating | Same |
| `ane-embedding` (CoreML/ANE) and `llama-embedding` (GGUF) backends, `model-loader` | Embeddings come from `../FoundationModelsRouter` (MLX); no hand-rolled ANE |
| MCP tool layer (`swissarmyhammer-tools` dispatch, schema) and any server surface | Consumer wraps ops as FoundationModels `Tool`s in a higher-level package |
| YAML server-spec registry + `include_dir!` embedding | Specs become plain Swift values (see LSP registry) |
| `ReadOnlyFollower` errors, residual-writer defenses | No second writer exists |

## Source material (Rust → Swift)

| Area | Rust source | Swift home |
|---|---|---|
| Workspace lifecycle, SQLite schema, cleanup, invalidation | `crates/swissarmyhammer-code-context/{workspace,db,cleanup,invalidation}.rs` | `Sources/CodeContextKit/Index/` |
| Tree-sitter registry + semantic chunking | `crates/swissarmyhammer-treesitter/{language,chunk}.rs` | `Sources/CodeContextKit/TreeSitter/` |
| TS call-edge heuristic | `crates/swissarmyhammer-code-context/ts_callgraph.rs` | `Sources/CodeContextKit/TreeSitter/` |
| Hybrid ranker (BM25 + trigram + cosine, RRF) | `crates/swissarmyhammer-search/` | `Sources/CodeContextKit/Search/` |
| LSP transport, session, daemon, supervisor | `crates/swissarmyhammer-lsp/{client,session,daemon,supervisor,types,diagnostics}.rs` | `Sources/CodeContextKit/LSP/` |
| LSP background indexer (documentSymbol + call hierarchy → SQLite) | `crates/swissarmyhammer-code-context/{lsp_worker,lsp_communication,lsp_indexer}.rs` | `Sources/CodeContextKit/Index/` |
| Layered cascade (LiveLsp → LspIndex → TreeSitter → None) | `crates/swissarmyhammer-code-context/layered_context.rs` | `Sources/CodeContextKit/Ops/` |
| Query ops | `crates/swissarmyhammer-code-context/ops/*.rs` | `Sources/CodeContextKit/Ops/` |
| Diagnose + settle engine | `crates/swissarmyhammer-diagnostics/{diagnose,settle,record}.rs` | `Sources/CodeContextKit/Diagnostics/` |
| Project detection (marker files) | `crates/swissarmyhammer-project-detection/` | `Sources/CodeContextKit/Projects/` |

## Package shape

```
CodeContextKit/
  Package.swift            // swift-tools-version 6.1+, macOS 27 (floor inherited
                           // from FoundationModelsRouter)
  Sources/CodeContextKit/
    CodeContext.swift      // public facade (actor)
    Index/                 // SQLite store, walker/reconciler, workers, watcher
    TreeSitter/            // grammar registry, chunker, ts call edges, AST query
    Search/                // BM25, trigram, cosine, RRF fusion
    LSP/                   // transport, session, daemon, supervisor, registry
    Diagnostics/           // diagnose, settle, report types
    Ops/                   // one file per operation, layered cascade
    Projects/              // project-type detection
    Embedding/             // TextEmbedding protocol + FoundationModelsRouter adapter
    Logging/               // os.Logger subsystem/category constants
  Tests/CodeContextKitTests/
```

### Dependencies

- `../FoundationModelsRouter` (local path) — embeddings via `RoutedEmbedder`
  (`embed([String]) async throws -> [[Float]]`, L2-normalized, runtime `dimension`).
- **SwiftTreeSitter** (ChimeHQ) + per-language grammar packages.
- **GRDB** for SQLite (WAL, migrations, `DatabasePool` for concurrent reads).
  Alternative: raw `sqlite3` C API — more code, no dep. Recommend GRDB.
- Nothing else. No Yams (registry is Swift code), no swift-log (see Logging).

## Logging — the answer

**Use `os.Logger` (Apple unified logging) directly.** Rationale:

- The macOS 27 floor (inherited from FoundationModelsRouter) makes this an
  Apple-only package; the usual reason to prefer the `swift-log` facade
  (cross-platform backends) does not apply.
- Unified logging is structured, near-zero-cost when not captured, has built-in
  privacy redaction, and is queryable after the fact:
  `log stream --predicate 'subsystem == "com.swissarmyhammer.CodeContextKit"'`
  or Console.app — exactly what you want when a language server dies at 2am.
- Categories map onto the Rust `tracing` targets we're porting:

```swift
enum Log {
    static let subsystem = "com.swissarmyhammer.CodeContextKit"
    static let lsp        = Logger(subsystem: subsystem, category: "lsp")        // spawn/exit/restart/handshake
    static let lspWire    = Logger(subsystem: subsystem, category: "lsp-wire")   // request/response ids (.debug)
    static let index      = Logger(subsystem: subsystem, category: "index")      // walk/reconcile/chunk counts
    static let watcher    = Logger(subsystem: subsystem, category: "watcher")
    static let embedding  = Logger(subsystem: subsystem, category: "embedding")
    static let search     = Logger(subsystem: subsystem, category: "search")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
```

Log levels mirror the Rust code: state transitions at `.debug`, spawn/restart/
shutdown at `.info`/`.notice`, unexpected exits and handshake failures at
`.error` with the captured stderr tail. Child-process stderr is drained and
re-logged line-by-line at `.debug` (same as Rust's `StderrFilter` path).

If we ever want the host app to intercept logs programmatically, we can add a
minimal event-callback seam later — but don't build it now.

## Architecture

### The index (SQLite, same schema)

Keep the Rust schema nearly verbatim — it's proven and simple:

- `indexed_files(file_path PK, content_hash, file_size, last_seen_at, ts_indexed, lsp_indexed, embedded)` — per-layer dirty flags
- `ts_chunks(file_path FK CASCADE, byte/line ranges, text, symbol_path, embedding BLOB?)` — little-endian Float32 blob
- `lsp_symbols(id PK, name, kind, file_path FK CASCADE, ranges, detail)`
- `lsp_call_edges(caller_id, callee_id, files, from_ranges, source: 'lsp'|'treesitter')`

Location: `<root>/.code-context/index.db`, WAL mode, dir self-gitignored —
same as Rust, so both implementations could even share on-disk conventions.

**Startup reconcile** (`startup_cleanup` port): gitignore-aware walk
(replicate `ignore::WalkBuilder` semantics — honor `.gitignore`, skip hidden
and the `.code-context` dir), SHA-256 first-16-bytes content hash computed
concurrently (TaskGroup), then: deleted → DELETE (cascades), changed → mark
all layers dirty, new → INSERT dirty.

**Indexing workers** (structured-concurrency tasks owned by the `CodeContext` actor):

1. *Tree-sitter worker* — drain `ts_indexed = 0`: parse → chunk (definition
   node kinds → `SemanticChunk` with qualified `symbol_path`) → embed chunks
   (batched through the injected embedder; skip gracefully if unavailable,
   leaving `embedded = 0`) → write chunks + heuristic call edges → mark done.
   Parsing/embedding happen outside any DB transaction.
2. *LSP worker* (one per running daemon) — drain `lsp_indexed = 0` for that
   server's extensions: `didOpen` → `documentSymbol` (flatten to qualified
   symbols) → `prepareCallHierarchy`/`outgoingCalls` per function-like symbol →
   `didClose` → persist symbols + edges (`source = 'lsp'`) → mark done.
   Includes the Rust invalidation rule: when a file's symbol set shrinks,
   files with edges into removed symbols get `lsp_indexed = 0`.

**File watching**: FSEvents (recursive on root) debounced ~1s, filtered to
source extensions → mark dirty / delete rows → nudge workers. This replaces
Rust's `notify`/`async-watcher`; `FanoutWatcher` collapses to direct calls.

### Tree-sitter layer

- `LanguageRegistry`: static table of `(name, Language, extensions)` using
  SwiftTreeSitter + grammar SPM packages. Extraction stays **node-kind driven**
  (port `EMBEDDABLE_NODE_KINDS` / `CONTAINER_KINDS` tables and the name-field
  heuristics) — no `.scm` files, matching the Rust design.
- Start with a pragmatic language set rather than all 30 (see Open Questions).
- `queryAST` op compiles user S-expression queries at runtime against files on
  disk (SwiftTreeSitter supports this directly).

### Search

Pure-Swift port of `swissarmyhammer-search`: BM25 corpus, character-trigram
Dice, cosine over chunk embeddings, fused with Reciprocal Rank Fusion, two
weighted fields (`symbol_path` ×5, body ×1), graceful degradation when a
signal is absent (e.g. embeddings not done → keyword-only), and an
`IndexingProgress` note on results while embedding is incomplete. Brute-force
in-memory scan of embedded chunks — no vector DB, same as Rust.

### Embeddings

CodeContextKit defines a tiny seam and never owns model lifecycle:

```swift
public protocol TextEmbedding: Sendable {
    var dimension: Int { get }
    func embed(_ texts: [String]) async throws -> [[Float]]
}
```

- Shipped adapter: `RoutedEmbedderAdapter` wrapping FoundationModelsRouter's
  `RoutedEmbedder` (which already has exactly this shape).
- The **host app** resolves the Router profile and injects the embedder.
  Reason: `Router` allows one resident profile at a time and resolving one
  loads two LLMs alongside the embedder — that lifecycle belongs to the app,
  not to a library that merely consumes vectors.
- Tests inject a deterministic fake (hash-based vectors); no models, no
  downloads, no Metal in CI.
- Query text is embedded with the same embedder at search time; if the stored
  dimension differs from the current embedder's, treat all chunks as
  un-embedded and re-embed (dimension recorded in a small `meta` table).

### Project detection

Port of `swissarmyhammer-project-detection` — pure filesystem inspection, no
LSP involved. It answers "what kinds of code live under this root?" and is
what decides which language servers to spawn.

- **When**: runs inside `context.start()`, before any daemon spawns. Also
  callable on demand as `detectProjects()` (re-scans, refreshes
  `state.projects`).
- **Input**: the `rootDirectory` the `CodeContext` was constructed with —
  detection never takes its own path parameter.
- **How**: gitignore-aware walk looking for marker files —
  `Package.swift`/`*.xcodeproj` → swift, `Cargo.toml` → rust,
  `package.json`/`tsconfig.json` → javascript/typescript, `go.mod` → go,
  `pyproject.toml`/`setup.py`/`requirements.txt` → python,
  `pom.xml`/`build.gradle` → java, `*.csproj`/`*.sln` → c#,
  `composer.json` → php, `CMakeLists.txt`/`Makefile` → c/cpp (same marker
  table as the Rust crate). One directory can match **multiple types**, and a
  monorepo yields one `DetectedProject(type, directory)` per hit.
- **Output → servers**: the union of detected types maps through the
  `ServerSpec` registry, **deduped by command**, so a polyglot monorepo with
  six `package.json`s still runs exactly one `typescript-language-server`.
  Every daemon is initialized with the workspace `rootDirectory` as its
  `rootUri` — no per-sub-project roots, same simplification as Rust.
- Results land in `state.projects` and drive `state.servers`; a missing
  server binary shows up there as `.notFound` with its install hint rather
  than failing `start()`.

### LSP subsystem

Direct port of `swissarmyhammer-lsp`, minus election. All mutex-guarded shared
state becomes actors.

- **`ServerSpec` registry**: the 12 Rust YAML specs become a static Swift
  array — `command, args, projectTypes, languageIds, fileExtensions,
  startupTimeout (30s), healthCheckInterval (60s), installHint`. Adding a
  server = adding a value. (Drop the `doctor:` blocks for now.)
- **Typed Swift API, no JSON-RPC layer.** The servers are external stdio
  processes whose only wire format is JSON-RPC, so `Content-Length` framing
  and message encoding exist — but strictly as a **private wire codec inside
  the server connection**, never as an abstraction or API. Nothing above the
  connection ever sees a method string, an id, or raw JSON. The seam the rest
  of the package (and tests) program against is a typed protocol:

  ```swift
  protocol LanguageServerConnection: Actor {
      func documentSymbols(in: DocumentURI) async throws -> [DocumentSymbol]
      func definition(in: DocumentURI, at: Position) async throws -> [Location]
      func hover(in: DocumentURI, at: Position) async throws -> Hover?
      func references(in: DocumentURI, at: Position) async throws -> [Location]
      func outgoingCalls(of: CallHierarchyItem) async throws -> [CallHierarchyOutgoingCall]
      // … one method per LSP capability we use (~17 total), typed in/out
      func didOpen/didChange/didSave/didClose(...)
      var serverNotifications: AsyncStream<ServerNotification> { get }  // publishDiagnostics
  }
  ```

  Request/response payloads are small hand-written `Codable` structs for just
  the methods we use — not a full LSP type library, no ChimeHQ dependency.
  Id-matching, the 30s per-request timeout, and the reader loop live inside
  the concrete `ProcessLanguageServerConnection`; tests use an in-memory fake
  conforming to the same protocol and never touch JSON.
- **`LspSession`** (actor): open-document set with `DocState(version, textHash)`,
  `syncOpen` (open-or-refresh, no-op-change suppression), per-URI diagnostics
  cache + `AsyncStream` fan-out (replaces tokio broadcast), `pullDiagnostics`
  (`textDocument/diagnostic`), `isReady` flag (flipped on ServerCancelled /
  ContentModified "still loading" replies), `resetDocuments()` on restart.
- **`LspDaemon`** (actor, one child process each) — the state machine:
  `notStarted → starting → running(pid) → failed(reason, attempts) →
  shuttingDown`, observable via `AsyncStream`. Lifecycle:
  1. Locate binary on PATH (miss → `.notFound` + install hint logged once).
  2. Spawn with piped stdio; stderr drained on a background task → `.debug` log.
  3. `initialize` (rootUri, empty capabilities — same optimistic stance as
     Rust: no capability gating, empty/null results mean "no data") then
     `initialized`, bounded by `startupTimeout`; on failure capture a stderr
     tail into the error and kill the child.
  4. **Health + auto-restart**: health check = process-exit detection
     (termination handler / periodic check every 60s). On unexpected exit:
     log `.error` with exit status, clear transport, `session.resetDocuments()`,
     state `.failed`, then restart with backoff **1, 2, 4, 8, 16, 32, 60 (cap)
     seconds**, giving up after **5 consecutive failures** (state stays
     `.failed`, visible in `lspStatus()`). Success resets the counter.
     `forceRestart()` resets the counter and restarts immediately.
  5. Graceful shutdown: `shutdown` request → `exit` notification → wait,
     bounded by 5s grace, else SIGKILL.
- **`LspSupervisor`** (actor): detect project types under root (marker files:
  `Package.swift`, `Cargo.toml`, `package.json`, `go.mod`, …), map to specs,
  **dedupe by command** (one daemon per server binary per workspace), own the
  daemons + the 60s health loop, expose `status()`, `forceRestart(command:)`,
  `shutdown()`, and `session(forFileExtension:)`.

### Observable state for SwiftUI (in-memory)

The kit unifies everything it knows — detected projects, LSP daemon health,
index progress, diagnostics — into one in-memory, SwiftUI-bindable model,
following the same pattern FoundationModelsRouter uses for
`ResolutionProgress`:

```swift
@MainActor @Observable
public final class CodeContextState {
    public private(set) var rootDirectory: URL             // the workspace this state describes
    public private(set) var projects: [DetectedProject]    // filled by detection during start()
    public private(set) var servers: [ServerStatus]        // per daemon: state, pid, restarts, lastError
    public private(set) var indexing: IndexProgress        // files walked/parsed/embedded/lsp-indexed, per layer
    public private(set) var diagnostics: [DocumentURI: [Diagnostic]]  // live cache, updated as servers publish
    public private(set) var isReady: Bool                  // all layers drained, servers settled
}
```

**How you get to it — vended off the `CodeContext` instance.** There is no
global; state is strictly per-workspace, scoped to the `CodeContext` that
owns it:

```swift
// The path under consideration enters exactly once, at construction.
let context = try await CodeContext(rootDirectory: repoURL, embedder: embedder)
try await context.start()

let state = context.state   // nonisolated let — created in init, same
                            // instance for the context's lifetime, safe to
                            // hand straight to a SwiftUI view
```

- One `CodeContext` per root directory; two workspaces = two contexts, two
  `state` objects, two indexes, two supervisor fleets. Nothing shared.
- `state` is a `nonisolated public let` on the `CodeContext` actor — grabbing
  the reference needs no `await`; reading its properties is main-actor
  (SwiftUI's home) by construction.
- `CodeContext` publishes into it (hopping to the main actor) from the
  workers, the supervisor's health loop, and the session's diagnostics
  stream — a SwiftUI harness just binds to it.
- This replaces the Rust side's status polling (`get status`, `lsp status`)
  as the *primary* surface; the async snapshot methods (`indexStatus()`,
  `lspStatus()`) remain as conveniences that read the same state.
- Query APIs stay `async` methods returning plain `Sendable` value types —
  results are request/response, not observable state.

### Layered ops

`LayeredContext` cascade, same semantics and provenance tags:

`liveLSP → lspIndex → treeSitter → none` — each op tries the live session
(`syncOpen` + request), falls back to indexed LSP symbols/edges, then
tree-sitter chunks, and returns an empty result tagged `.none` rather than
erroring when no layer has data.

Ops surface (public methods on `CodeContext`, mirroring the Rust op set):

- **Indexed**: `getSymbol`, `searchSymbol`, `listSymbols(file:)`, `grepCode`,
  `searchCode` (hybrid), `findDuplicates`, `queryAST`, `callGraph`
  (BFS over edges, direction in/out/both, depth ≤5), `blastRadius`
  (inbound BFS, hops ≤10, per-hop file aggregation), `indexStatus`,
  `rebuildIndex(layer:)`, `detectProjects`.
- **Live LSP**: `definition`, `typeDefinition`, `hover`, `references`,
  `implementations`, `codeActions`, `renameEdits` (prepare+rename under one
  transport hold), `inboundCalls`, `workspaceSymbols`, `lspStatus`.
- **Diagnostics**: `diagnostics(scope: .workingTree | .file(glob) | .sha(range))`
  with the settle engine — seed from cache, wait for **300ms quiescence**,
  hard timeout **5s** → `pending: true`; fold in only *broken* one-hop
  dependents (from the call-edge index); severity floor defaults to warning.
  Clock injected for tests.

## Port order (each step compiles + is tested before the next)

1. **Package scaffold** — Package.swift (deps: FoundationModelsRouter path,
   SwiftTreeSitter, GRDB, initial grammars), `Log` constants, error enum,
   CI-able `swift test`.
2. **Store** — GRDB schema + migrations, dirty-flag helpers, Float32-blob
   embedding codec, meta table (embedder dimension).
3. **Walker/reconciler** — gitignore-aware walk, concurrent hashing,
   reconcile logic (port of `startup_cleanup`), `.code-context/` bootstrap.
4. **Tree-sitter layer** — registry, chunker (`EMBEDDABLE_NODE_KINDS`,
   `symbol_path` qualification), TS worker writing chunks; then the TS
   call-edge heuristic; then `queryAST`.
5. **Embedding seam** — `TextEmbedding` protocol, fake for tests,
   `RoutedEmbedderAdapter`, batch embedding inside the TS worker.
6. **Search** — BM25/trigram/cosine/RRF port + `searchCode`, `findDuplicates`.
7. **Indexed ops** — `getSymbol` (match tiers Exact/Suffix/CaseInsensitive/Fuzzy),
   `searchSymbol`, `listSymbols`, `grepCode`, `callGraph`, `blastRadius`, status ops.
8. **LSP connection + session** — `LanguageServerConnection` protocol + typed
   payload structs, `ProcessLanguageServerConnection` (private wire codec,
   id-matching, timeouts) + in-memory fake, `LspSession` actor with
   diagnostics cache.
9. **LSP daemon + supervisor** — state machine, handshake, health loop,
   backoff auto-restart, graceful shutdown, project detection, registry.
10. **LSP indexer worker** — documentSymbol/call-hierarchy → SQLite,
    invalidation propagation; wire `source_layer` cascade into ops.
11. **Live ops** — definition/hover/references/…/renameEdits/workspaceSymbols.
12. **Diagnostics** — settle engine (injected clock), scopes, dependents
    fold-in, report types.
13. **Observable state** — `CodeContextState` (@MainActor @Observable), wired
    from workers, supervisor health loop, and diagnostics stream; snapshot
    methods read the same state.
14. **Watcher + facade polish** — FSEvents pipeline, `CodeContext.start()/stop()`
    lifecycle, end-to-end integration test against a fixture repo (and, gated
    on tool availability, a live `sourcekit-lsp` smoke test).

## Testing strategy

- Every LSP layer sits behind `LanguageServerConnection` — unit tests use a
  scripted in-memory fake (canned typed responses, induced crashes to exercise
  backoff/restart) and never touch JSON; the wire codec gets its own small
  round-trip tests.
- One gated integration test drives real `sourcekit-lsp` (present wherever
  Xcode is) end-to-end: spawn → index → definition → kill -9 the child →
  assert auto-restart and recovery.
- Embedding tests use the deterministic fake; a gated integration test uses
  the real FoundationModelsRouter profile.
- Search ranker gets golden tests ported from the Rust crate's cases.
- Fixture mini-repos under `Tests/Fixtures/` for walk/reconcile/watch tests.

## Open questions to discuss

1. ~~Grammar set for v1~~ **Resolved: TIOBE-driven.** Criterion: TIOBE top 15
   (June 2026) — the cutoff lands at Swift, #15 — ∩ languages the Rust side
   already has grammars + chunk rules for, plus the formats an agent harness
   always meets.
   - From TIOBE 1–15: **python, c, c++, java, c#, javascript, sql, rust, go,
     php, swift** (skipping Visual Basic #7, R #9, Delphi #10, Scratch #11 —
     no sah chunk rules, negligible agent-harness value).
   - Plus: **typescript/tsx** (TIOBE ranks it separately but it's essential),
     and **json, yaml, markdown, bash** for config/docs/scripts.
   - LSP registry already covers the compiled ones (`jdtls`, `omnisharp`,
     `intelephense`, `clangd`, `rust-analyzer`, `gopls`, `pylsp`,
     `typescript-language-server`, `sourcekit-lsp`); sql/json/yaml/markdown
     are tree-sitter-only layers, same as Rust.
   - Long tail (kotlin, ruby, scala, dart, …) rides on the registry design:
     one table row + one grammar dep each, added on demand.
2. ~~LSP transport: hand-rolled vs ChimeHQ~~ **Resolved: no JSON-RPC layer at
   all.** Typed Swift API (`LanguageServerConnection`) is the only seam; the
   JSON-RPC wire encoding is a private detail of the process-backed
   implementation. No ChimeHQ/JSONRPC dependency.
3. **Server registry as Swift code** (no YAML/Yams) — fine, or do you want
   drop-in file extensibility from day one?
4. **Index compatibility.** Keep `.code-context/index.db` name/schema so Rust
   sah and CodeContextKit could share a workspace index, or rename (e.g. own
   subdir) to avoid two writers ever colliding? Plan currently assumes same
   conventions but nothing shared at runtime.
5. **Live-op set for v1** — all ten live LSP ops, or trim (e.g. defer
   codeActions/renameEdits) to land the core faster?
