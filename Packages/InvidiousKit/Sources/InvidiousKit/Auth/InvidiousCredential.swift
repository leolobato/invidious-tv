import Foundation

/// How a client proves who it is to an Invidious instance.
public enum InvidiousCredential: Hashable, Sendable {
    /// Session cookie obtained from the username and password login form.
    case sid(String)
    /// Access token from `/authorize_token`, kept in the URL-form-encoded shape the callback delivered.
    /// Sent as `Authorization: Bearer <token>`; the server decodes it the same way.
    case token(String)

    private static let tokenPrefix = "token:"

    /// Single-string form for the keychain. Plain SIDs stay as they were stored by earlier versions.
    public var storageString: String {
        switch self {
        case .sid(let sid): return sid
        case .token(let token): return Self.tokenPrefix + token
        }
    }

    public init(storageString: String) {
        if storageString.hasPrefix(Self.tokenPrefix) {
            self = .token(String(storageString.dropFirst(Self.tokenPrefix.count)))
        } else {
            self = .sid(storageString)
        }
    }

    public var isToken: Bool {
        if case .token = self { return true }
        return false
    }
}

public extension SessionStore {
    func credential(for profileID: UUID) throws -> InvidiousCredential? {
        try sid(for: profileID).map(InvidiousCredential.init(storageString:))
    }

    func setCredential(_ credential: InvidiousCredential, for profileID: UUID) throws {
        try setSID(credential.storageString, for: profileID)
    }
}
