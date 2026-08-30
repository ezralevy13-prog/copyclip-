import Foundation

/// Content-addressed file storage for representations too large to sit inline
/// in the database.
///
/// Addressing by SHA-256 means copying the same screenshot ten times costs one
/// file on disk, and it makes eviction safe: a blob is deletable exactly when
/// no representation row still references its hash.
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
        // Already stored: content-addressed, so identical hash means identical
        // bytes and there is nothing to do.
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

    // MARK: - Accounting

    /// Total bytes across blobs and thumbnails.
    func diskUsage() -> Int64 {
        [root, thumbnailRoot].reduce(0) { total, directory in
            total + directorySize(directory)
        }
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Removes any blob file no longer referenced by a representation row.
    /// Called after eviction, where deleting rows is what orphans the files.
    func collectGarbage(referencedHashes: Set<String>) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            if !referencedHashes.contains(url.lastPathComponent) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
