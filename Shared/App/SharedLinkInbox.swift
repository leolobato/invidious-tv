import Foundation
import InvidiousKit

/// Hand-off file the share extension writes and the app consumes on activation.
struct SharedLinkInbox {
    let fileURL: URL?

    init(appGroup: String = Bundle.main.object(forInfoDictionaryKey: "InvidiousAppGroup") as? String ?? "") {
        fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("pending-link.txt")
    }

    func store(videoID: String) {
        guard let fileURL else { return }
        try? Data(videoID.utf8).write(to: fileURL, options: .atomic)
    }

    /// Returns and clears the pending video ID.
    func takeVideoID() -> String? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        let id = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }
}
