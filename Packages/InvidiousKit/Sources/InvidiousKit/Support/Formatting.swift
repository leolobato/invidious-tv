import Foundation

/// Display formatting shared by all platforms.
public enum VideoFormatting {
    /// `1:02:03` or `4:05`.
    public static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// `1.2M views`, `43K views`, `987 views`.
    public static func viewCount(_ count: Int?) -> String? {
        guard let count else { return nil }
        return "\(compact(count)) views"
    }

    /// `1.2M`, `43K`, `987`.
    public static func compact(_ count: Int) -> String {
        let value = Double(count)
        switch count {
        case 1_000_000_000...:
            return trimmed(value / 1_000_000_000) + "B"
        case 1_000_000...:
            return trimmed(value / 1_000_000) + "M"
        case 1_000...:
            return trimmed(value / 1_000) + "K"
        default:
            return String(count)
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    /// `3 days ago`, using the system relative formatter.
    public static func relativeDate(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
