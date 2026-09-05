import Foundation

public enum InvidiousError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidCredentials
    case unauthorized
    case httpStatus(Int, String?)
    case invalidResponse
    case decoding(String)
    case network(String)
    case loginDisabled
    case tokenRejected
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The instance URL is not valid."
        case .invalidCredentials:
            return "Wrong username or password."
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return "Server error \(code): \(message)"
            }
            return "Server error \(code)."
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .decoding(let detail):
            return "Could not read the server response. \(detail)"
        case .network(let detail):
            return detail
        case .loginDisabled:
            return "Login is disabled on this instance."
        case .tokenRejected:
            return "The instance did not accept the token from your phone. Please try again."
        case .emptyResponse:
            return "The instance returned no data for this video. If it is a live stream or premiere, it may not have started yet."
        }
    }

    /// True when the failure means the stored session is no longer valid.
    public var isSessionExpired: Bool {
        self == .unauthorized
    }
}
