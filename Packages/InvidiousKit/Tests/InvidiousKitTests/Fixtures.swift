import Foundation
import InvidiousKit

enum Fixtures {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw NSError(domain: "Fixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing fixture \(name)"])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try InvidiousDecoder.make().decode(T.self, from: data(name))
    }

    static func video(_ id: String, length: Int = 600, upcoming: Bool = false) -> VideoSummary {
        VideoSummary(videoId: id, title: "Video \(id)", author: "Author", authorId: "UC\(id)", lengthSeconds: length, isUpcoming: upcoming)
    }
}
