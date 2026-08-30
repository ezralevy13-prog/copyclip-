import Foundation
import CryptoKit

enum Hashing {
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Stable content hash for a whole pasteboard snapshot.
    ///
    /// Feeds every (index, uti, bytes) triple into the digest in a canonical
    /// order so that the same copy always produces the same hash regardless of
    /// the order the pasteboard happened to report its types in.
    static func snapshotHash(_ snapshot: PasteboardSnapshot) -> String {
        var hasher = SHA256()
        for (index, item) in snapshot.items.enumerated() {
            for uti in item.representations.keys.sorted() {
                guard let payload = item.representations[uti] else { continue }
                hasher.update(data: Data("\(index)\u{0}\(uti)\u{0}\(payload.count)\u{0}".utf8))
                hasher.update(data: payload)
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
