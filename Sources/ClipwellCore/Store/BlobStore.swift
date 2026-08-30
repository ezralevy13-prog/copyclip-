import Foundation

/// Content-addressed file storage for representations too large to sit inline
/// in the database.
///
/// Addressing by SHA-256 means copying the same screenshot ten times costs one
/// file on disk. Reference counting is tracked in SQLite by `HistoryStore`, not
/// here -- this type only owns bytes on disk.
final class BlobStore {
    /// Below this, bytes live inline in the row -- fewer files, faster reads.
    static let inlineThreshold = 64 * 1024

    private let root: URL
    private let thumbnailRoot: URL
    private let fileManager = FileManager.default

    init(root: URL) throws {
        self.root = root.appendingPathComponent("blobs", isDirectory: true)
        self.thumbnailRoot = root.appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: self.root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: self.thumbnailRoot, withIntermediateDirectories: true)
    }

    /// Two-character fan-out directory, so a 100k-item history doesn't put
    /// 100k files in one directory.
    private func url(forHash hash: String) -> URL {
        let prefix = String(hash.prefix(2))
        return root.appendingPathComponent(prefix, isDirectory: true)
                   .appendingPathComponent(hash)
    }

    @discardableResult
    func write(_ data: Data) throws -> String {
        let hash = Hashing.sha256Hex(data)
        let destination = url(forHash: hash)
        // Content-addressed, so an identical hash means identical bytes and
        // there is nothing to write.
        if fileManager.fileExists(atPath: destination.path) { return hash }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return hash
    }

    func read(hash: String) -> Data? {
        try? Data(contentsOf: url(forHash: hash))
    }

    func delete(hash: String) {
        try? fileManager.removeItem(at: url(forHash: hash))
    }

    // MARK: - Thumbnails

    func writeThumbnail(_ data: Data, for contentHash: String) throws -> String {
        let destination = thumbnailRoot.appendingPathComponent("\(contentHash).jpg")
        try data.write(to: destination, options: .atomic)
        return destination.path
    }

    func deleteThumbnail(atPath path: String) {
        try? fileManager.removeItem(atPath: path)
    }

    // MARK: - Reconciliation

    /// Every blob hash currently on disk.
    ///
    /// This walks the whole tree, so it is only used by the startup
    /// reconciliation pass -- never on the capture path.
    func allHashesOnDisk() -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var hashes: Set<String> = []
        for case let url as URL in enumerator {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            if isRegular { hashes.insert(url.lastPathComponent) }
        }
        return hashes
    }
}
