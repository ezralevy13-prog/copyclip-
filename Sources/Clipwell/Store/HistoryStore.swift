import Foundation
import AppKit

/// Owns the database, the blob store, and every rule about what gets kept.
///
/// All work happens on a private serial queue; the capture timer and the UI
/// both talk to it from outside, so the queue is what keeps it consistent.
final class HistoryStore {

    static let didChangeNotification = Notification.Name("ClipwellHistoryDidChange")

    private let database: SQLiteDatabase
    private let blobs: BlobStore
    private let queue = DispatchQueue(label: "com.ezralevy.clipwell.store")
    private var hasFTS = false

    let storageRoot: URL

    init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Clipwell", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        self.storageRoot = support
        self.database = try SQLiteDatabase(path: support.appendingPathComponent("history.sqlite").path)
        self.blobs = try BlobStore(root: support)
        try createSchema()
    }

    // MARK: - Schema

    private func createSchema() throws {
        try database.execute("""
            CREATE TABLE IF NOT EXISTS items (
                id               INTEGER PRIMARY KEY AUTOINCREMENT,
                content_hash     TEXT NOT NULL UNIQUE,
                kind             TEXT NOT NULL,
                preview_text     TEXT NOT NULL DEFAULT '',
                search_text      TEXT NOT NULL DEFAULT '',
                source_bundle_id TEXT,
                source_app_name  TEXT,
                created_at       REAL NOT NULL,
                last_used_at     REAL NOT NULL,
                use_count        INTEGER NOT NULL DEFAULT 0,
                pinned           INTEGER NOT NULL DEFAULT 0,
                byte_size        INTEGER NOT NULL DEFAULT 0,
                thumb_path       TEXT,
                meta             TEXT
            );
            """)

        // pb_index preserves multi-item pasteboards (a Finder copy of five
        // files is five pasteboard items, not one), so paste can rebuild them.
        try database.execute("""
            CREATE TABLE IF NOT EXISTS representations (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                item_id     INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                pb_index    INTEGER NOT NULL DEFAULT 0,
                uti         TEXT NOT NULL,
                inline_data BLOB,
                blob_hash   TEXT,
                byte_size   INTEGER NOT NULL DEFAULT 0
            );
            """)

        try database.execute("CREATE INDEX IF NOT EXISTS idx_reps_item ON representations(item_id);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_reps_hash ON representations(blob_hash);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_items_recent ON items(pinned DESC, last_used_at DESC);")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind);")

        // FTS5 ships in Apple's SQLite, but degrade to LIKE rather than refuse
        // to launch if this build lacks it.
        hasFTS = database.tryExecute("CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(search_text);")
        if !hasFTS {
            Log.store.warning("FTS5 unavailable; falling back to LIKE search")
        }
    }

    // MARK: - Insert

    /// Stores a snapshot, or bumps the existing row if we've seen it before.
    /// Returns the item id, or nil if the snapshot was rejected.
    @discardableResult
    func insert(_ snapshot: PasteboardSnapshot) -> Int64? {
        queue.sync {
            do {
                return try insertLocked(snapshot)
            } catch {
                Log.store.error("insert failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    private func insertLocked(_ snapshot: PasteboardSnapshot) throws -> Int64? {
        let hash = Hashing.snapshotHash(snapshot)

        // Re-copying something already in the history should promote it to the
        // top, not create a duplicate row.
        var existingID: Int64?
        try database.query("SELECT id FROM items WHERE content_hash = ? LIMIT 1;", [.text(hash)]) { row in
            existingID = row.int64(0)
        }
        if let existingID {
            try database.run(
                "UPDATE items SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?;",
                [.date(Date()), .integer(existingID)]
            )
            notifyChange()
            return existingID
        }

        var snapshot = snapshot
        var classification = ContentClassifier.classify(snapshot)

        // Transcode uncompressed TIFF to PNG before storing. A retina screenshot
        // arrives as ~20 MB of TIFF and leaves as ~1 MB of PNG; without this a
        // day of screenshotting is measured in gigabytes.
        if classification.kind == .image {
            snapshot = transcodeImages(in: snapshot)
            classification = ContentClassifier.classify(snapshot)
        }

        var thumbnailPath: String?
        if classification.kind == .image, let image = snapshot.bestImage(),
           let thumbnail = ImageUtil.thumbnail(from: image.data, maxPixel: 400) {
            thumbnailPath = try? blobs.writeThumbnail(thumbnail, for: hash)
        }

        let itemID: Int64 = try database.transaction {
            try database.run("""
                INSERT INTO items
                    (content_hash, kind, preview_text, search_text, source_bundle_id,
                     source_app_name, created_at, last_used_at, use_count, pinned,
                     byte_size, thumb_path, meta)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?);
                """, [
                    .text(hash),
                    .text(classification.kind.rawValue),
                    .text(String(classification.previewText.prefix(4096))),
                    .text(String(classification.searchText.prefix(16384))),
                    .optionalText(snapshot.sourceBundleID),
                    .optionalText(snapshot.sourceAppName),
                    .date(snapshot.capturedAt),
                    .date(snapshot.capturedAt),
                    .int(snapshot.totalByteSize),
                    .optionalText(thumbnailPath),
                    .optionalText(classification.meta.encoded())
                ])

            let newID = database.lastInsertRowID

            for (index, item) in snapshot.items.enumerated() {
                for (uti, data) in item.representations {
                    if data.count <= BlobStore.inlineThreshold {
                        try database.run("""
                            INSERT INTO representations (item_id, pb_index, uti, inline_data, byte_size)
                            VALUES (?, ?, ?, ?, ?);
                            """, [.integer(newID), .int(index), .text(uti), .blob(data), .int(data.count)])
                    } else {
                        let blobHash = try blobs.write(data)
                        try database.run("""
                            INSERT INTO representations (item_id, pb_index, uti, blob_hash, byte_size)
                            VALUES (?, ?, ?, ?, ?);
                            """, [.integer(newID), .int(index), .text(uti), .text(blobHash), .int(data.count)])
                    }
                }
            }

            if hasFTS {
                try database.run(
                    "INSERT INTO items_fts (rowid, search_text) VALUES (?, ?);",
                    [.integer(newID), .text(classification.searchText)]
                )
            }
            return newID
        }

        try enforceLimitsLocked()
        notifyChange()
        return itemID
    }

    private func transcodeImages(in snapshot: PasteboardSnapshot) -> PasteboardSnapshot {
        var snapshot = snapshot
        for index in snapshot.items.indices {
            guard let tiff = snapshot.items[index].representations[UTIs.tiff] else { continue }
            // Only replace TIFF when nothing already offers a compressed form
            // and the re-encode is actually smaller.
            let hasCompressed = snapshot.items[index].representations.keys.contains {
                $0 == UTIs.png || $0 == UTIs.jpeg || $0 == UTIs.heic
            }
            guard !hasCompressed, let png = ImageUtil.transcodeToPNG(tiff), png.count < tiff.count else { continue }
            snapshot.items[index].representations[UTIs.tiff] = nil
            snapshot.items[index].representations[UTIs.png] = png
        }
        return snapshot
    }

    // MARK: - Read

    func items(matching searchQuery: String = "", kind: ClipKind? = nil, limit: Int = 500) -> [ClipItem] {
        queue.sync {
            do {
                return try itemsLocked(matching: searchQuery, kind: kind, limit: limit)
            } catch {
                Log.store.error("query failed: \(String(describing: error), privacy: .public)")
                return []
            }
        }
    }

    private func itemsLocked(matching searchQuery: String, kind: ClipKind?, limit: Int) throws -> [ClipItem] {
        var clauses: [String] = []
        var bindings: [SQLiteValue] = []

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            if hasFTS, let matchExpression = Self.ftsQuery(from: trimmed) {
                clauses.append("id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)")
                bindings.append(.text(matchExpression))
            } else {
                clauses.append("(search_text LIKE ? OR preview_text LIKE ?)")
                let pattern = "%\(trimmed)%"
                bindings.append(.text(pattern))
                bindings.append(.text(pattern))
            }
        }

        if let kind {
            clauses.append("kind = ?")
            bindings.append(.text(kind.rawValue))
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        bindings.append(.int(limit))

        var results: [ClipItem] = []
        try database.query("""
            SELECT id, content_hash, kind, preview_text, source_bundle_id, source_app_name,
                   created_at, last_used_at, use_count, pinned, byte_size, thumb_path, meta
            FROM items
            \(whereClause)
            ORDER BY pinned DESC, last_used_at DESC
            LIMIT ?;
            """, bindings) { row in
            results.append(ClipItem(
                id: row.int64(0),
                contentHash: row.string(1),
                kind: ClipKind(rawValue: row.string(2)) ?? .text,
                previewText: row.string(3),
                sourceBundleID: row.optionalString(4),
                sourceAppName: row.optionalString(5),
                createdAt: row.date(6),
                lastUsedAt: row.date(7),
                useCount: row.int(8),
                pinned: row.bool(9),
                byteSize: row.int(10),
                thumbnailPath: row.optionalString(11),
                meta: ClipMeta.decode(row.optionalString(12))
            ))
        }
        return results
    }

    /// Builds a prefix-matching FTS expression, quoting each token so that
    /// user input can't be read as FTS operator syntax.
    static func ftsQuery(from input: String) -> String? {
        let tokens = input
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        // Splitting on non-alphanumerics already strips anything FTS could read
        // as operator syntax; quoting each token is belt and braces so that a
        // future change to the tokenizer can't turn user input into a query.
        let quote = "\""
        let quoted = tokens.map { token -> String in
            let escaped = token.replacingOccurrences(of: quote, with: quote + quote)
            return quote + escaped + quote + "*"
        }
        return quoted.joined(separator: " AND ")
    }

    /// Rebuilds the full pasteboard contents for an item.
    func representations(for itemID: Int64) -> [[String: Data]] {
        queue.sync {
            var byIndex: [Int: [String: Data]] = [:]
            do {
                try database.query("""
                    SELECT pb_index, uti, inline_data, blob_hash
                    FROM representations WHERE item_id = ? ORDER BY pb_index, id;
                    """, [.integer(itemID)]) { row in
                    let index = row.int(0)
                    let uti = row.string(1)
                    let data: Data?
                    if let inline = row.optionalData(2) {
                        data = inline
                    } else if let hash = row.optionalString(3) {
                        data = self.blobs.read(hash: hash)
                    } else {
                        data = nil
                    }
                    guard let data else { return }
                    byIndex[index, default: [:]][uti] = data
                }
            } catch {
                Log.store.error("representation load failed: \(String(describing: error), privacy: .public)")
            }
            return byIndex.keys.sorted().compactMap { byIndex[$0] }
        }
    }

    /// Full-size image bytes for the preview pane, loaded only on demand.
    func fullImageData(for itemID: Int64) -> Data? {
        let groups = representations(for: itemID)
        for group in groups {
            for uti in UTIs.imagePreferenceOrder {
                if let data = group[uti] { return data }
            }
        }
        return nil
    }

    func plainText(for itemID: Int64) -> String? {
        let groups = representations(for: itemID)
        for group in groups {
            for uti in UTIs.plainTextFamily {
                if let data = group[uti], let text = String(data: data, encoding: .utf8) { return text }
            }
        }
        return nil
    }

    // MARK: - Mutate

    func setPinned(_ pinned: Bool, itemID: Int64) {
        queue.sync {
            try? database.run("UPDATE items SET pinned = ? WHERE id = ?;", [.bool(pinned), .integer(itemID)])
        }
        notifyChange()
    }

    func markUsed(itemID: Int64) {
        queue.sync {
            try? database.run(
                "UPDATE items SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?;",
                [.date(Date()), .integer(itemID)]
            )
        }
        notifyChange()
    }

    func delete(itemID: Int64) {
        queue.sync {
            do {
                try deleteItemsLocked(ids: [itemID])
                try collectGarbageLocked()
            } catch {
                Log.store.error("delete failed: \(String(describing: error), privacy: .public)")
            }
        }
        notifyChange()
    }

    /// Clears history. Pinned items survive unless `includingPinned`.
    func clearAll(includingPinned: Bool) {
        queue.sync {
            do {
                let predicate = includingPinned ? "" : "WHERE pinned = 0"
                var ids: [Int64] = []
                try database.query("SELECT id FROM items \(predicate);") { row in ids.append(row.int64(0)) }
                try deleteItemsLocked(ids: ids)
                try collectGarbageLocked()
            } catch {
                Log.store.error("clear failed: \(String(describing: error), privacy: .public)")
            }
        }
        notifyChange()
    }

    private func deleteItemsLocked(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        // Thumbnails aren't reference-counted, so remove them explicitly.
        for id in ids {
            try database.query("SELECT thumb_path FROM items WHERE id = ?;", [.integer(id)]) { row in
                if let path = row.optionalString(0) { self.blobs.deleteThumbnail(atPath: path) }
            }
        }
        try database.transaction {
            for id in ids {
                try database.run("DELETE FROM representations WHERE item_id = ?;", [.integer(id)])
                try database.run("DELETE FROM items WHERE id = ?;", [.integer(id)])
                if hasFTS {
                    try database.run("DELETE FROM items_fts WHERE rowid = ?;", [.integer(id)])
                }
            }
        }
    }

    // MARK: - Eviction

    /// Enforces both caps. Pinned items are never evicted and don't count
    /// toward the item limit.
    private func enforceLimitsLocked() throws {
        let preferences = Preferences.shared
        var doomed: [Int64] = []

        // Item-count cap.
        var unpinnedCount = 0
        try database.query("SELECT COUNT(*) FROM items WHERE pinned = 0;") { row in
            unpinnedCount = row.int(0)
        }
        let overflow = unpinnedCount - preferences.maxItems
        if overflow > 0 {
            try database.query("""
                SELECT id FROM items WHERE pinned = 0
                ORDER BY last_used_at ASC LIMIT ?;
                """, [.int(overflow)]) { row in
                doomed.append(row.int64(0))
            }
        }

        if !doomed.isEmpty {
            try deleteItemsLocked(ids: doomed)
            try collectGarbageLocked()
            doomed.removeAll()
        }

        // Disk cap. Measured against real on-disk bytes rather than the sum of
        // byte_size, because content-addressing means duplicates share storage.
        let capBytes = Int64(preferences.maxDiskMegabytes) * 1024 * 1024
        var usage = blobs.diskUsage()
        guard usage > capBytes else { return }

        var candidates: [(id: Int64, size: Int64)] = []
        try database.query("""
            SELECT id, byte_size FROM items WHERE pinned = 0 ORDER BY last_used_at ASC;
            """) { row in
            candidates.append((row.int64(0), Int64(row.int(1))))
        }

        var toDelete: [Int64] = []
        for candidate in candidates {
            if usage <= capBytes { break }
            toDelete.append(candidate.id)
            usage -= candidate.size
        }
        if !toDelete.isEmpty {
            try deleteItemsLocked(ids: toDelete)
            try collectGarbageLocked()
        }
    }

    private func collectGarbageLocked() throws {
        var referenced: Set<String> = []
        try database.query("SELECT DISTINCT blob_hash FROM representations WHERE blob_hash IS NOT NULL;") { row in
            if let hash = row.optionalString(0) { referenced.insert(hash) }
        }
        blobs.collectGarbage(referencedHashes: referenced)
    }

    // MARK: - Stats

    struct Stats {
        var itemCount: Int
        var pinnedCount: Int
        var diskBytes: Int64
    }

    func stats() -> Stats {
        queue.sync {
            var itemCount = 0
            var pinnedCount = 0
            try? database.query("SELECT COUNT(*), COALESCE(SUM(pinned), 0) FROM items;") { row in
                itemCount = row.int(0)
                pinnedCount = row.int(1)
            }
            return Stats(itemCount: itemCount, pinnedCount: pinnedCount, diskBytes: blobs.diskUsage())
        }
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
