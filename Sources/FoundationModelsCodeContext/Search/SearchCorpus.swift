import Foundation
import GRDB
import FoundationModelsRanker

/// A cached, contiguous snapshot of one workspace's `ts_chunks` table, ready
/// for BM25/trigram keyword scoring and `vDSP_mmul` cosine scoring — the
/// data `SearchCode.run(corpus:embedder:query:topK:weights:)` ranks against.
///
/// See plan.md "Search", "Where the cosines happen": chunk embeddings live in
/// one contiguous row-major `[Float]` matrix (`chunkCount` rows ×
/// `embeddingDimension` columns) rather than as `chunkCount` separate
/// arrays, so scoring every chunk against a query vector is one
/// `vDSP_mmul` matrix–vector product instead of `chunkCount` separate
/// dot-product loops. BM25/trigram data is likewise precomputed once per
/// chunk when the snapshot is built — tokenizing and trigramming
/// `chunkCount` texts is the expensive part — rather than once per query.
public struct SearchCorpusSnapshot: Sendable {
    /// Each chunk's `ts_chunks.id`, positionally aligned with every other
    /// array in this type.
    public let chunkIds: [Int64]

    /// Each chunk's file path, positionally aligned with `chunkIds`.
    public let filePaths: [String]

    /// Each chunk's qualified symbol path, positionally aligned with
    /// `chunkIds`.
    public let symbolPaths: [String]

    /// Each chunk's full source text, positionally aligned with `chunkIds`.
    public let texts: [String]

    /// Each chunk's meta-type, positionally aligned with `chunkIds`.
    public let kinds: [SymbolMetaType]

    /// Each chunk's zero-based start line, positionally aligned with
    /// `chunkIds`.
    public let startLines: [Int]

    /// Each chunk's zero-based end line, positionally aligned with
    /// `chunkIds`.
    public let endLines: [Int]

    /// Whether each chunk carries a usable (non-`NULL`,
    /// `embeddingDimension`-length) embedding, positionally aligned with
    /// `chunkIds`. A chunk without one contributes an all-zero row to
    /// `embeddingMatrix`, which — since every real embedding is
    /// L2-normalized — scores an exact `0.0` cosine against any query,
    /// matching `Signals.cosine`'s documented "no embedding" value.
    public let embeddedFlags: [Bool]

    /// The dimension of every row in `embeddingMatrix`; `0` if no chunk in
    /// the corpus has an embedding yet.
    public let embeddingDimension: Int

    /// The corpus's embeddings as one contiguous, row-major `chunkCount ×
    /// embeddingDimension` matrix — row `i` is `chunkIds[i]`'s embedding (or
    /// an all-zero row if `embeddedFlags[i]` is `false`). Not `public`:
    /// `cosineScores(queryVector:)` is the sanctioned way to score it.
    let embeddingMatrix: [Float]

    /// Each chunk's precomputed BM25/trigram statistics — `symbolPaths[i]`
    /// as the primary field (weighted `BM25.primaryFieldWeight`), `texts[i]`
    /// as the body field (weighted `BM25.bodyFieldWeight`) — positionally
    /// aligned with `chunkIds`. `FoundationModelsRanker.RankedDocument` carries the
    /// weighted term frequency, term set, document length, and both trigram
    /// sets the BM25/trigram scoring stages consume.
    let rankedDocuments: [RankedDocument]

    /// The number of chunks in this snapshot.
    public var chunkCount: Int { chunkIds.count }

    /// The number of chunks with `embeddedFlags[i] == true`.
    public var embeddedChunkCount: Int { embeddedFlags.count { $0 } }

    /// Scores every chunk's cosine similarity against `queryVector` with one
    /// `vDSP_mmul` matrix–vector product over `embeddingMatrix`.
    ///
    /// Both `embeddingMatrix`'s rows and `queryVector` must already be
    /// L2-normalized (the injected `TextEmbedding` guarantees this for its
    /// own output), so cosine similarity reduces to a plain dot product —
    /// see plan.md "Search", "Where the cosines happen".
    ///
    /// - Parameter queryVector: The L2-normalized query embedding, of length
    ///   `embeddingDimension`.
    /// - Returns: One score per chunk, positionally aligned with `chunkIds`;
    ///   every score is `0.0` if `queryVector`'s length doesn't match
    ///   `embeddingDimension` or the corpus has no chunks.
    public func cosineScores(queryVector: [Float]) -> [Float] {
        CosineScoring.matvecScores(
            matrix: embeddingMatrix,
            rowCount: chunkCount,
            dimension: embeddingDimension,
            queryVector: queryVector
        )
    }
}

/// Owns one workspace's lazily-loaded `SearchCorpusSnapshot` cache, kept
/// current by **incremental, per-file re-index** rather than a wholesale
/// reload on every write.
///
/// See plan.md "Search", "Where the cosines happen": a `SearchCorpus` is
/// meant to be created once (e.g. by `CodeContext`) and reused across every
/// `SearchCode.run(corpus:embedder:query:topK:weights:)` call. A file that
/// finishes indexing shows up on the very next call — no explicit
/// invalidation call, no process restart — because `snapshot()` reacts to
/// `store.generation` advancing.
///
/// **Incremental lifecycle.** The corpus keeps a per-file cache of already
/// tokenized/trigrammed `RankedDocument`s and decoded embedding vectors,
/// keyed by `ts_chunks.file_path` — the same additive, group-keyed streaming
/// shape FoundationModelsRanker's `SearchCorpus` uses for session transcripts
/// (its group key is a session id; ours is a file path). When `generation`
/// advances, `snapshot()` runs one cheap scan of `ts_chunks` (ids and
/// embedding byte lengths only — no text, no embedding blobs) to find which
/// files' chunks actually changed, then re-tokenizes and re-decodes **only
/// those files**, reusing every untouched file's precompute verbatim. A file
/// whose rows are gone is dropped; the packed cosine matrix is repacked from
/// the cached vectors (a `memcpy` of already-persisted embeddings — no
/// re-embedding). The BM25 corpus globals (`idf`/`avgdl`) aren't cached here
/// at all: `SearchCode` rebuilds them per query from the live snapshot, so
/// they are always correct after any incremental splice, exactly as after a
/// from-scratch load.
///
/// **Full reload stays the cold-start path and the fallback.** The very first
/// `snapshot()` (empty cache) loads every row in one query — identical to the
/// pre-incremental behavior — and any state the incremental path can't reason
/// about locally (a file whose signature changed) resolves to re-loading that
/// file's rows from `store`, the durable source of truth.
///
/// Why this doesn't wrap `FoundationModelsRanker.SearchCorpus` directly: that
/// value type builds each row's `RankedDocument` from the item's *id* as the
/// BM25/trigram primary field, whereas this corpus needs the chunk's
/// *symbol path* as the primary field (heavily weighted, `BM25.primaryFieldWeight`)
/// with the chunk's integer id kept separately for identity and result
/// mapping — plus per-chunk file path, kind, line range, and a packed cosine
/// matrix the Ranker's type doesn't carry. So this adopts the Ranker's
/// additive streaming *pattern* and its `RankedDocument` precompute primitive,
/// rather than its corpus container.
public actor SearchCorpus {
    private let store: Store

    /// The current cache: the generation it was built at, the per-file
    /// entries it was assembled from (for the next incremental diff), and the
    /// assembled snapshot itself. `nil` until the first `snapshot()`.
    private var cache: Cache?

    /// The number of chunks re-tokenized (a fresh `RankedDocument` built)
    /// during the most recent `snapshot()` that rebuilt the cache — the whole
    /// corpus on a cold start, only the changed files' chunks on an
    /// incremental update, and `0` when a generation bump changed no
    /// `ts_chunks` row. Internal, for the perf-guard tests.
    private(set) var lastBuildReTokenizedChunkCount = 0

    /// The number of embedding blobs decoded during the most recent
    /// `snapshot()` that rebuilt the cache — a subset of
    /// `lastBuildReTokenizedChunkCount` (only chunks that carry an embedding).
    /// Internal, for the cosine repack tests.
    private(set) var lastBuildReDecodedChunkCount = 0

    /// Creates a corpus cache over `store`, with no snapshot loaded yet —
    /// the first `snapshot()` call performs the initial load.
    ///
    /// - Parameter store: The workspace's index store `snapshot()` loads
    ///   `ts_chunks` from.
    public init(store: Store) {
        self.store = store
    }

    /// Returns the current corpus snapshot, incrementally re-indexing any
    /// file whose chunks changed since the cache was built (or loading the
    /// whole corpus on the first call).
    ///
    /// - Returns: The up-to-date snapshot.
    /// - Throws: Rethrows `Store`'s storage errors.
    public func snapshot() async throws -> SearchCorpusSnapshot {
        let currentGeneration = store.generation
        if let cache, cache.generation == currentGeneration {
            return cache.snapshot
        }
        return try await rebuild(currentGeneration: currentGeneration)
    }

    // MARK: - Cache types

    /// The corpus's cached state between `snapshot()` calls.
    private struct Cache {
        /// The `store.generation` this cache is valid for.
        var generation: Int

        /// The per-file entries the snapshot was assembled from, keyed by
        /// file path — the input to the next incremental diff.
        var files: [String: FileEntry]

        /// The assembled snapshot handed to callers.
        var snapshot: SearchCorpusSnapshot
    }

    /// One file's cached precompute: the change signature that decides
    /// whether it must be reloaded, and its already-processed chunks.
    private struct FileEntry: Sendable {
        /// This file's chunks' `(id, embeddingByteCount)` pairs in id order —
        /// the cheap fingerprint compared against a fresh scan to detect a
        /// re-chunk (new ids), an embedding fill-in, or an embedding dimension
        /// change (byte count moves) (see `SignatureEntry`).
        let signature: [SignatureEntry]

        /// This file's fully-processed chunks, in id order.
        let chunks: [CachedChunk]
    }

    /// One chunk's contribution to a file's change signature: its id and its
    /// embedding blob's byte length (`0` when it has no embedding). Captures
    /// every way a chunk can change the snapshot without reading any text or
    /// decoding any vector:
    /// - a re-chunk assigns new ids (bodies/symbols/kinds/lines only ever
    ///   change together with a new id, since `TreeSitterWorker` re-chunks a
    ///   file by `DELETE`+`INSERT` with fresh autoincrement ids);
    /// - embedding a chunk moves its byte length from `0` to non-zero;
    /// - an embedder **dimension** change re-embeds in place (same id,
    ///   still non-`NULL`) but at a different vector width, which the byte
    ///   length reflects — `idf`/`avgdl` aside, this is the case a bare
    ///   presence flag would miss, leaving stale vectors and a wrong
    ///   `embeddingDimension` cached.
    ///
    /// `length(embedding)` is computed by SQLite without materializing the
    /// blob, so the scan stays cheap. The one residual it can't see is an
    /// in-place re-embed that keeps the exact same id **and** byte width but a
    /// different vector value — only reachable by forcing a re-embed
    /// (`IndexAdmin.rebuildIndex(layer: .embedding)`) under a *different*
    /// same-dimension embedder; short of hashing every blob on every scan
    /// (which would defeat the cheap-scan design) that case resolves on the
    /// next real re-chunk or dimension change.
    private struct SignatureEntry: Equatable, Sendable {
        let id: Int64
        let embeddingByteCount: Int
    }

    /// One `ts_chunks` row after its expensive per-chunk precompute — the
    /// tokenized/trigrammed `RankedDocument` and the decoded embedding — so a
    /// snapshot rebuild that reuses this chunk pays neither cost again.
    private struct CachedChunk: Sendable {
        let id: Int64
        let filePath: String
        let symbolPath: String
        let text: String
        let kind: SymbolMetaType
        let startLine: Int
        let endLine: Int

        /// The decoded embedding, or `nil` if the row had none. Repacked into
        /// the snapshot's contiguous matrix by `assemble(files:)` with no
        /// re-decode.
        let vector: [Float]?

        /// The precomputed BM25/trigram statistics — symbol path as the
        /// primary field, body text as the body field.
        let rankedDocument: RankedDocument
    }

    /// One `ts_chunks` row as loaded from disk, before its precompute.
    private struct ChunkRow: Sendable {
        let id: Int64
        let filePath: String
        let startLine: Int
        let endLine: Int
        let text: String
        let symbolPath: String
        let kind: SymbolMetaType
        let embedding: Data?
    }

    // MARK: - Rebuild

    /// Rebuilds the cache for `currentGeneration`: a full load on cold start,
    /// otherwise an incremental splice of only the files whose chunks
    /// changed.
    private func rebuild(currentGeneration: Int) async throws -> SearchCorpusSnapshot {
        guard let existing = cache else {
            // Cold start: load every file in one query, exactly as before the
            // incremental path existed.
            let files = try await loadAllFiles()
            recordWork(in: files.values)
            let snapshot = assemble(files: files)
            cache = Cache(generation: currentGeneration, files: files, snapshot: snapshot)
            return snapshot
        }

        // Incremental: one cheap scan tells us which files changed.
        let signatures = try await loadSignatures()
        let cachedPaths = Set(existing.files.keys)
        let livePaths = Set(signatures.keys)

        let removedPaths = cachedPaths.subtracting(livePaths)
        let changedPaths = signatures.compactMap { path, signature in
            existing.files[path]?.signature == signature ? nil : path
        }

        guard !removedPaths.isEmpty || !changedPaths.isEmpty else {
            // Generation advanced without touching any `ts_chunks` row (e.g. a
            // dirty-flag flip): reuse the snapshot untouched, just revalidate
            // it for this generation so the next call short-circuits.
            recordWork(in: EmptyCollection())
            cache = Cache(generation: currentGeneration, files: existing.files, snapshot: existing.snapshot)
            return existing.snapshot
        }

        let reloaded = try await loadFiles(paths: changedPaths)

        var files = existing.files
        for path in removedPaths {
            files[path] = nil
        }
        for (path, entry) in reloaded {
            files[path] = entry
        }

        // Record the reload cost once, synchronously, after the last `await`
        // — never incrementing shared counters across a suspension point,
        // where actor reentrancy could interleave another `snapshot()`.
        recordWork(in: reloaded.values)

        let snapshot = assemble(files: files)
        cache = Cache(generation: currentGeneration, files: files, snapshot: snapshot)
        return snapshot
    }

    /// Records this rebuild's re-tokenize/re-decode cost into the
    /// instrumentation seams from the entries it actually (re)built — the
    /// whole corpus on a cold start, only the reloaded files on an incremental
    /// update, and nothing (`0`) when no file changed.
    ///
    /// - Parameter entries: the `FileEntry`s this rebuild freshly precomputed.
    private func recordWork(in entries: some Collection<FileEntry>) {
        lastBuildReTokenizedChunkCount = entries.reduce(0) { $0 + $1.chunks.count }
        lastBuildReDecodedChunkCount = entries.reduce(0) { $0 + $1.chunks.lazy.filter { $0.vector != nil }.count }
    }

    // MARK: - Loading

    /// Scans every `ts_chunks` row's id and embedding byte length — no text,
    /// no embedding blobs (`length(embedding)` is evaluated by SQLite without
    /// materializing the blob) — grouped into the per-file change signatures
    /// the incremental diff compares against the cache. `O(rows)` but cheap:
    /// the expensive tokenize/decode work is deferred to only the files this
    /// scan proves changed.
    private func loadSignatures() async throws -> [String: [SignatureEntry]] {
        let rows: [(filePath: String, entry: SignatureEntry)] = try await store.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT \(Schema.TsChunks.filePath), \(Schema.TsChunks.id), \
                       COALESCE(LENGTH(\(Schema.TsChunks.embedding)), 0) AS embeddingByteCount \
                FROM \(Schema.TsChunks.table) ORDER BY \(Schema.TsChunks.filePath), \(Schema.TsChunks.id)
                """
            ).map { row in
                (
                    filePath: row[Schema.TsChunks.filePath],
                    entry: SignatureEntry(id: row[Schema.TsChunks.id], embeddingByteCount: row["embeddingByteCount"])
                )
            }
        }

        var signatures: [String: [SignatureEntry]] = [:]
        for row in rows {
            signatures[row.filePath, default: []].append(row.entry)
        }
        return signatures
    }

    /// Loads and precomputes every `ts_chunks` row in one query — the
    /// cold-start bulk load — grouped into per-file entries.
    private func loadAllFiles() async throws -> [String: FileEntry] {
        let rows = try await fetchRows(sql: """
            \(Self.rowColumns) \
            FROM \(Schema.TsChunks.table) ORDER BY \(Schema.TsChunks.filePath), \(Schema.TsChunks.id)
            """)

        var rowsByFile: [String: [ChunkRow]] = [:]
        for row in rows {
            rowsByFile[row.filePath, default: []].append(row)
        }
        return rowsByFile.mapValues { makeFileEntry(rows: $0) }
    }

    /// Loads and precomputes exactly `paths`' rows — the incremental reload —
    /// one query per file so the bound-parameter count stays fixed regardless
    /// of corpus size.
    private func loadFiles(paths: [String]) async throws -> [String: FileEntry] {
        var entries: [String: FileEntry] = [:]
        for path in paths {
            let rows = try await fetchRows(
                sql: """
                    \(Self.rowColumns) \
                    FROM \(Schema.TsChunks.table) WHERE \(Schema.TsChunks.filePath) = ? ORDER BY \(Schema.TsChunks.id)
                    """,
                arguments: [path]
            )
            entries[path] = makeFileEntry(rows: rows)
        }
        return entries
    }

    /// The `SELECT` column list shared by `loadAllFiles()` and
    /// `loadFiles(paths:)`, which differ only in their `WHERE`/`ORDER BY`.
    private static let rowColumns = """
        SELECT \(Schema.TsChunks.id), \(Schema.TsChunks.filePath), \(Schema.TsChunks.startLine), \
               \(Schema.TsChunks.endLine), \(Schema.TsChunks.text), \(Schema.TsChunks.symbolPath), \
               \(Schema.TsChunks.kind), \(Schema.TsChunks.embedding)
        """

    /// Runs `sql` (with `arguments`) and maps each result row into a
    /// `ChunkRow`.
    private func fetchRows(sql: String, arguments: StatementArguments = StatementArguments()) async throws -> [ChunkRow] {
        try await store.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                ChunkRow(
                    id: row[Schema.TsChunks.id],
                    filePath: row[Schema.TsChunks.filePath],
                    startLine: row[Schema.TsChunks.startLine],
                    endLine: row[Schema.TsChunks.endLine],
                    text: row[Schema.TsChunks.text],
                    symbolPath: row[Schema.TsChunks.symbolPath],
                    kind: SymbolMetaType(rawValue: row[Schema.TsChunks.kind]) ?? .other,
                    embedding: row[Schema.TsChunks.embedding]
                )
            }
        }
    }

    // MARK: - Precompute & assembly

    /// Precomputes one file's `rows` (in id order) into a `FileEntry`: each
    /// chunk's decoded embedding vector and its tokenized/trigrammed
    /// `RankedDocument`, plus the file's `(id, embeddingByteCount)` change
    /// signature. Pure — the rebuild counts its cost from the returned entries
    /// (`recordWork(in:)`), so this never touches the instrumentation seams
    /// itself.
    private func makeFileEntry(rows: [ChunkRow]) -> FileEntry {
        let chunks = rows.map { row in
            CachedChunk(
                id: row.id,
                filePath: row.filePath,
                symbolPath: row.symbolPath,
                text: row.text,
                kind: row.kind,
                startLine: row.startLine,
                endLine: row.endLine,
                vector: row.embedding.map { EmbeddingCodec.decode($0) },
                rankedDocument: RankedDocument(primaryText: row.symbolPath, bodyText: row.text)
            )
        }
        let signature = rows.map { SignatureEntry(id: $0.id, embeddingByteCount: $0.embedding?.count ?? 0) }
        return FileEntry(signature: signature, chunks: chunks)
    }

    /// Assembles the cached `files` into a `SearchCorpusSnapshot`: flattens
    /// every file's chunks into one id-ordered sequence (so `chunkIds` match a
    /// from-scratch load's `ORDER BY id`), then repacks the contiguous cosine
    /// matrix from the already-decoded per-chunk vectors — a `memcpy`, never a
    /// re-decode or re-embed.
    private func assemble(files: [String: FileEntry]) -> SearchCorpusSnapshot {
        let chunks = files.values.flatMap(\.chunks).sorted { $0.id < $1.id }
        let embeddingDimension = chunks.lazy.compactMap { $0.vector?.count }.first ?? 0

        var embeddingMatrix: [Float] = []
        embeddingMatrix.reserveCapacity(chunks.count * embeddingDimension)
        var embeddedFlags: [Bool] = []
        embeddedFlags.reserveCapacity(chunks.count)

        for chunk in chunks {
            Self.appendEmbeddingRow(
                vector: chunk.vector,
                embeddingDimension: embeddingDimension,
                matrix: &embeddingMatrix,
                embeddedFlags: &embeddedFlags
            )
        }

        return SearchCorpusSnapshot(
            chunkIds: chunks.map(\.id),
            filePaths: chunks.map(\.filePath),
            symbolPaths: chunks.map(\.symbolPath),
            texts: chunks.map(\.text),
            kinds: chunks.map(\.kind),
            startLines: chunks.map(\.startLine),
            endLines: chunks.map(\.endLine),
            embeddedFlags: embeddedFlags,
            embeddingDimension: embeddingDimension,
            embeddingMatrix: embeddingMatrix,
            rankedDocuments: chunks.map(\.rankedDocument)
        )
    }

    /// Appends one chunk's row to `matrix` (and its flag to `embeddedFlags`):
    /// the cached vector if present and matching `embeddingDimension`, or an
    /// all-zero row otherwise (which scores an exact `0.0` cosine, matching
    /// `Signals.cosine`'s documented "no embedding" value).
    private static func appendEmbeddingRow(
        vector: [Float]?,
        embeddingDimension: Int,
        matrix: inout [Float],
        embeddedFlags: inout [Bool]
    ) {
        if let vector, embeddingDimension > 0, vector.count == embeddingDimension {
            matrix.append(contentsOf: vector)
            embeddedFlags.append(true)
            return
        }
        matrix.append(contentsOf: [Float](repeating: 0.0, count: embeddingDimension))
        embeddedFlags.append(false)
    }
}
