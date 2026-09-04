import Foundation

/// One household member: an Invidious account on an instance.
public struct Profile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var username: String
    public var instanceURL: URL
    public var colorIndex: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        username: String,
        instanceURL: URL,
        colorIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.instanceURL = instanceURL
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }

    /// Up to two initials for the avatar tile.
    public var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.isEmpty, let first = name.first {
            return String(first).uppercased()
        }
        return letters.joined()
    }
}
