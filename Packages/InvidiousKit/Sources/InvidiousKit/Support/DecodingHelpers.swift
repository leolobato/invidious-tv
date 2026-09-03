import Foundation

extension KeyedDecodingContainer {
    /// Decodes an Int that the API may encode as either a number or a numeric string.
    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }

    /// Decodes a Unix timestamp that the API encodes as an integer in most places and as an
    /// RFC 3339 string in `recommendedVideos`.
    func decodeFlexibleTimestamp(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            if let number = Int(string) { return number }
            if let date = ISO8601DateFormatter().date(from: string) {
                return Int(date.timeIntervalSince1970)
            }
        }
        return nil
    }

    /// Decodes a String that the API may encode as either a string or a number.
    func decodeFlexibleString(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

public enum InvidiousDecoder {
    public static func make() -> JSONDecoder {
        JSONDecoder()
    }
}
