import Foundation
import GRDB

/// Drains `ts_indexed = 0` files from a `Store`, parses and chunks each via
/// `Chunker`, and writes the resulting `SemanticChunk`s into `ts_chunks`.
///
/// Port of the tree-sitter portion of the Rust
/// `index_discovered_files_with_embedder`
/// (`swissarmyhammer-tools/src/mcp/tools/code_context/mod.rs`), scoped to
/// this task: chunk extraction and storage only — embedding is a separate,
/// later worker (plan.md "Indexing workers"), so every written row's
/// `embedding` column stays `NULL`. Parsing (via
/// `Chunker.chunk(file:module:)`) always runs outside any database
/// transaction; only the `DELETE`+`INSERT` for a file's chunks and its
/// `ts_indexed` flag flip happen inside one `Store.write` block.
public enum TreeSitterWorker {
    /// Drains and processes every file with `ts_indexed = 0` in `store`.
    ///
    /// For each dirty file: reads its content from disk (relative to
    /// `rootDirectory`), looks up its `LanguageModule` by extension, chunks
    /// it, replaces its `ts_chunks` rows, and marks it indexed. A file is
    /// always marked indexed, so it isn't retried forever, but the two ways
    /// chunking can come up empty are handled differently: a file whose
    /// language module can't be resolved or can't be read as UTF-8 text
    /// skips the `ts_chunks` write entirely, leaving any existing rows from
    /// a prior successful pass untouched; a file that resolves and reads but
    /// fails to parse (or genuinely has no chunkable nodes) still runs the
    /// write, which — per `Chunker.chunk(file:module:)`'s empty-array
    /// contract for both cases — replaces its rows with none.
    ///
    /// - Parameters:
    ///   - store: The workspace's index store to drain and write into.
    ///   - rootDirectory: The workspace root dirty file paths are relative
    ///     to.
    /// - Returns: The number of dirty files drained this pass.
    /// - Throws: Rethrows `Store`'s storage errors.
    @discardableResult
    public static func run(store: Store, rootDirectory: URL) async throws -> Int {
        let dirtyPaths = try await store.drainTsDirty()

        for relativePath in dirtyPaths {
            if let chunks = readAndChunk(relativePath: relativePath, rootDirectory: rootDirectory) {
                try await writeChunks(chunks: chunks, filePath: relativePath, store: store)
            }
            try await store.markIndexed(filePath: relativePath, layer: .treeSitter)
        }

        return dirtyPaths.count
    }

    /// Reads `relativePath`'s content from disk and chunks it with its
    /// registered `LanguageModule`, or `nil` if the language module can't be
    /// resolved or the file can't be read as UTF-8 text.
    ///
    /// Runs entirely outside any database transaction.
    private static func readAndChunk(relativePath: String, rootDirectory: URL) -> [SemanticChunk]? {
        let fileExtension = URL(fileURLWithPath: relativePath).pathExtension
        guard let module = Languages.module(forFileExtension: fileExtension) else {
            Log.index.warning("no language module for \(relativePath, privacy: .public)")
            return nil
        }

        let fileURL = rootDirectory.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: fileURL), let contents = String(data: data, encoding: .utf8) else {
            Log.index.warning("failed to read \(relativePath, privacy: .public)")
            return nil
        }

        let file = SourceFile(relativePath: relativePath, contents: contents)
        return Chunker.chunk(file: file, module: module)
    }

    /// Replaces `filePath`'s `ts_chunks` rows with `chunks`, in one write
    /// transaction: deletes the file's existing rows (so a re-chunked,
    /// changed file doesn't accumulate stale rows alongside the new ones),
    /// then inserts each chunk with a `NULL` embedding.
    private static func writeChunks(chunks: [SemanticChunk], filePath: String, store: Store) async throws {
        try await store.write { db in
            try db.execute(
                sql: "DELETE FROM \(Schema.TsChunks.table) WHERE \(Schema.TsChunks.filePath) = ?",
                arguments: [filePath]
            )
            for chunk in chunks {
                try db.execute(
                    sql: """
                    INSERT INTO \(Schema.TsChunks.table)
                        (\(Schema.TsChunks.filePath), \(Schema.TsChunks.startByte), \(Schema.TsChunks.endByte), \
                         \(Schema.TsChunks.startLine), \(Schema.TsChunks.endLine), \(Schema.TsChunks.text), \
                         \(Schema.TsChunks.symbolPath), \(Schema.TsChunks.kind))
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        chunk.filePath, chunk.startByte, chunk.endByte,
                        chunk.startLine, chunk.endLine, chunk.text,
                        chunk.symbolPath, chunk.kind.rawValue,
                    ]
                )
            }
        }
    }
}
