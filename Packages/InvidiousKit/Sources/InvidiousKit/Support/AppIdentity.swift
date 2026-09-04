import Foundation

/// Identifiers derived from the configured bundle ID, so forks with their own bundle ID share nothing
/// with this project's builds.
///
/// The app and its extensions put `InvidiousAppBundleID` (the app's bundle ID, `$(APP_BUNDLE_ID)`) in
/// their Info.plist, so an extension resolves the same identifiers as its host app.
public enum AppIdentity {
    /// The app's bundle ID, even when running inside an extension.
    public static let baseBundleID: String = {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "InvidiousAppBundleID") as? String, !configured.isEmpty {
            return configured
        }
        return Bundle.main.bundleIdentifier ?? "invidious-client"
    }()

    /// Keychain service under which profile sessions are stored.
    public static var keychainService: String { baseBundleID + ".session" }

    /// Unified-log subsystem for the app's own messages.
    public static var logSubsystem: String { baseBundleID }

    /// Prefix for dispatch queue and thread names.
    public static func label(_ suffix: String) -> String { baseBundleID + "." + suffix }
}
