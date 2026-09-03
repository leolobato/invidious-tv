import SwiftUI

enum ProfilePalette {
    static let colors: [Color] = [
        Color(red: 0.91, green: 0.30, blue: 0.24),
        Color(red: 0.20, green: 0.60, blue: 0.86),
        Color(red: 0.18, green: 0.71, blue: 0.47),
        Color(red: 0.95, green: 0.61, blue: 0.07),
        Color(red: 0.61, green: 0.35, blue: 0.71),
        Color(red: 0.10, green: 0.74, blue: 0.61),
        Color(red: 0.90, green: 0.49, blue: 0.13),
        Color(red: 0.35, green: 0.40, blue: 0.85),
    ]

    static func color(index: Int) -> Color {
        colors[abs(index) % colors.count]
    }

    /// Stable color derived from an arbitrary string such as a channel ID.
    static func color(for key: String) -> Color {
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return colors[hash % colors.count]
    }
}
