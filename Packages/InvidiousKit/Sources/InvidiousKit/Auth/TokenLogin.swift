import Foundation
import Network

/// Sign-in through the instance's `/authorize_token` page, approved from another device.
///
/// The app shows a QR code for ``authorizeURL(instance:callback:)``. The phone opens it, signs in to
/// Invidious in its browser and approves; Invidious then redirects the browser to `callback` with the
/// token and username in the query, which ``TokenCallbackServer`` receives on the TV.
public enum TokenLogin {
    /// What the app needs. `POST:tokens/unregister` lets the profile revoke its own token when removed.
    public static let scopes = [":feed", ":subscriptions*", ":history*", ":playlists*", "POST:tokens/unregister"]

    public static let callbackPath = "/callback"

    public struct Result: Hashable, Sendable {
        public var token: String
        public var username: String?

        public init(token: String, username: String?) {
            self.token = token
            self.username = username
        }

        public var credential: InvidiousCredential { .token(token) }
    }

    public static func authorizeURL(instance: URL, callback: URL) -> URL? {
        var components = URLComponents(url: instance, resolvingAgainstBaseURL: false)
        components?.path = "/authorize_token"
        components?.queryItems = [
            URLQueryItem(name: "scopes", value: scopes.joined(separator: ",")),
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
        ]
        return components?.url
    }

    /// Callback the TV listens on. `host` is the TV's LAN address.
    public static func callbackURL(host: String, port: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = callbackPath
        return components.url
    }

    /// Parses the redirect Invidious sends the browser to. Returns nil when the token is missing.
    ///
    /// Invidious form-encodes the token JSON and then percent-encodes it again as a query value, so a
    /// single percent-decoding (what `URLComponents` does) leaves the exact string the API expects
    /// after `Bearer `. The username is additionally path-segment-encoded.
    public static func parseCallback(_ url: URL) -> Result? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.path == callbackPath,
              let items = components.queryItems else { return nil }
        var token: String?
        var username: String?
        for item in items {
            switch item.name {
            case "token": token = item.value
            case "username": username = item.value?.removingPercentEncoding
            default: break
            }
        }
        guard let token, !token.isEmpty else { return nil }
        if let name = username?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            username = name
        } else {
            username = nil
        }
        return Result(token: token, username: username)
    }
}

/// Minimal HTTP listener for the token callback. One-shot: stop it once a result arrives.
public final class TokenCallbackServer: @unchecked Sendable {
    public enum ServerError: Error, LocalizedError, Sendable {
        case failed(String)
        case stopped

        public var errorDescription: String? {
            switch self {
            case .failed(let detail): return "Could not listen for the phone: \(detail)"
            case .stopped: return "Sign-in was cancelled."
            }
        }
    }

    private let queue = DispatchQueue(label: "org.lobato.invidioustv.token-callback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var resultContinuation: CheckedContinuation<TokenLogin.Result, Error>?
    private var pendingResult: TokenLogin.Result?
    private var isStopped = false
    private let successPage: String

    /// - Parameter successPage: HTML shown in the phone's browser after the token was received.
    public init(successPage: String = TokenCallbackServer.defaultSuccessPage) {
        self.successPage = successPage
    }

    /// Starts listening on a random TCP port and returns it.
    public func start() async throws -> UInt16 {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters)
        } catch {
            throw ServerError.failed(error.localizedDescription)
        }
        lock.withLock { self.listener = listener }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let resumed = LockedFlag()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if resumed.trySet() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case .failed(let error):
                    if resumed.trySet() {
                        continuation.resume(throwing: ServerError.failed(error.localizedDescription))
                    } else {
                        self?.finish(.failure(ServerError.failed(error.localizedDescription)))
                    }
                case .cancelled:
                    if resumed.trySet() {
                        continuation.resume(throwing: ServerError.stopped)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }
    }

    /// Waits for the phone's browser to hit the callback. Throws when the server stops first.
    public func waitForResult() async throws -> TokenLogin.Result {
        try await withCheckedThrowingContinuation { continuation in
            let immediate: Swift.Result<TokenLogin.Result, Error>? = lock.withLock {
                if let pendingResult { return .success(pendingResult) }
                if isStopped { return .failure(ServerError.stopped) }
                resultContinuation = continuation
                return nil
            }
            if let immediate { continuation.resume(with: immediate) }
        }
    }

    public func stop() {
        finish(.failure(ServerError.stopped))
        let (listener, connections): (NWListener?, [NWConnection]) = lock.withLock {
            defer { self.listener = nil; self.connections = [:] }
            return (self.listener, Array(self.connections.values))
        }
        listener?.cancel()
        connections.forEach { $0.cancel() }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        lock.withLock { connections[ObjectIdentifier(connection)] = connection }
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .failed, .cancelled:
                self?.lock.withLock { _ = self?.connections.removeValue(forKey: ObjectIdentifier(connection)) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let error {
                _ = error
                connection.cancel()
                return
            }
            if let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
                self.handle(requestHead: head, on: connection)
            } else if isComplete || buffer.count > 65_536 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(requestHead: String, on connection: NWConnection) {
        let requestLine = requestHead.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(status: "400 Bad Request", body: "Bad request", on: connection)
            return
        }
        let target = String(parts[1])
        if let url = URL(string: "http://localhost\(target)"), let result = TokenLogin.parseCallback(url) {
            respond(status: "200 OK", body: successPage, on: connection)
            finish(.success(result))
        } else if target.hasPrefix(TokenLogin.callbackPath) {
            respond(status: "400 Bad Request", body: "<p>Invidious did not send a token. Please try again on your TV.</p>", on: connection)
        } else {
            respond(status: "404 Not Found", body: "Not found", on: connection)
        }
    }

    private func respond(status: String, body: String, on connection: NWConnection) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Swift.Result<TokenLogin.Result, Error>) {
        let continuation: CheckedContinuation<TokenLogin.Result, Error>? = lock.withLock {
            switch result {
            case .success(let value):
                if pendingResult == nil { pendingResult = value }
            case .failure:
                isStopped = true
            }
            // A stop after a result must not clobber the result.
            if case .failure = result, pendingResult != nil, resultContinuation == nil { return nil }
            defer { resultContinuation = nil }
            return resultContinuation
        }
        if let continuation {
            switch result {
            case .success(let value): continuation.resume(returning: value)
            case .failure(let error):
                if let pending = lock.withLock({ pendingResult }) {
                    continuation.resume(returning: pending)
                } else {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public static let defaultSuccessPage = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"><title>Invidious TV</title>
    <style>body{font-family:-apple-system,system-ui,sans-serif;background:#111;color:#eee;display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}
    div{padding:2em}h1{font-size:1.6em}p{color:#aaa}</style></head>
    <body><div><h1>Signed in</h1><p>You can close this page and go back to your Apple TV.</p></div></body></html>
    """
}

/// Thread-safe one-shot flag.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    /// Returns true the first time it is called.
    func trySet() -> Bool {
        lock.withLock {
            if value { return false }
            value = true
            return true
        }
    }
}

/// IPv4 addresses of the device on the local network, Wi-Fi and Ethernet first.
public enum LocalNetworkAddress {
    public static func ipv4Addresses() -> [String] {
        var addresses: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: interface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            guard !address.hasPrefix("169.254.") else { continue }
            addresses.append((name, address))
        }
        func rank(_ name: String) -> Int {
            if name == "en0" { return 0 }
            if name.hasPrefix("en") { return 1 }
            if name.hasPrefix("bridge") || name.hasPrefix("utun") || name.hasPrefix("awdl") || name.hasPrefix("llw") { return 3 }
            return 2
        }
        return addresses
            .filter { rank($0.name) < 3 }
            .sorted { rank($0.name) < rank($1.name) }
            .map(\.address)
    }
}
