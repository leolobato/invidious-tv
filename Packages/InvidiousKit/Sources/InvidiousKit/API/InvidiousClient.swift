import Foundation

/// HTTP client for one Invidious instance, optionally authenticated with a session ID or token.
///
/// The client is immutable; create a new one when the instance or credential changes.
public final class InvidiousClient: Sendable {
    public let baseURL: URL
    public let credential: InvidiousCredential?

    private let session: URLSession
    private let decoder = InvidiousDecoder.make()

    public init(baseURL: URL, credential: InvidiousCredential?, session: URLSession? = nil) {
        self.baseURL = baseURL
        self.credential = credential
        self.session = session ?? Self.makeSession()
    }

    public convenience init(baseURL: URL, sid: String? = nil, session: URLSession? = nil) {
        self.init(baseURL: baseURL, credential: sid.map(InvidiousCredential.sid), session: session)
    }

    /// The session cookie, when the client authenticates with one.
    public var sid: String? {
        if case .sid(let sid)? = credential { return sid }
        return nil
    }

    /// Returns a copy of this client authenticated with `sid`.
    public func authenticated(sid: String?) -> InvidiousClient {
        authenticated(credential: sid.map(InvidiousCredential.sid))
    }

    /// Returns a copy of this client authenticated with `credential`.
    public func authenticated(credential: InvidiousCredential?) -> InvidiousClient {
        InvidiousClient(baseURL: baseURL, credential: credential, session: session)
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    // MARK: - Public endpoints

    public func stats() async throws -> InstanceStats {
        try await get("/api/v1/stats")
    }

    public func trending() async throws -> [VideoSummary] {
        try await get("/api/v1/trending")
    }

    public func popular() async throws -> [VideoSummary] {
        try await get("/api/v1/popular")
    }

    /// Video details. With `proxy` the stream URLs go through the instance instead of googlevideo.
    public func video(id: String, proxy: Bool = false) async throws -> VideoDetails {
        try await get("/api/v1/videos/\(id)", query: proxy ? ["local": "true"] : [:])
    }

    public func channel(ucid: String) async throws -> Channel {
        try await get("/api/v1/channels/\(ucid)")
    }

    public func channelVideos(ucid: String, continuation: String? = nil) async throws -> ChannelVideosPage {
        var query: [String: String] = [:]
        if let continuation { query["continuation"] = continuation }
        return try await get("/api/v1/channels/\(ucid)/videos", query: query)
    }

    public func storyboards(videoID: String) async throws -> StoryboardsResponse {
        try await get("/api/v1/storyboards/\(videoID)")
    }

    /// Downloads and parses the WebVTT storyboard for a given sprite size.
    public func storyboardTrack(spec: StoryboardSpec) async throws -> StoryboardTrack {
        let url = try absoluteURL(spec.url)
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response, data: data)
        let text = String(decoding: data, as: UTF8.self)
        return StoryboardTrack.parse(webVTT: text, relativeTo: baseURL)
    }

    // MARK: - Comments

    public func comments(videoID: String, continuation: String? = nil) async throws -> CommentsPage {
        var query: [String: String] = [:]
        if let continuation { query["continuation"] = continuation }
        return try await get("/api/v1/comments/\(videoID)", query: query)
    }

    // MARK: - Search

    public func search(query: String, page: Int = 1, type: SearchType = .all) async throws -> [SearchItem] {
        try await get("/api/v1/search", query: ["q": query, "page": String(page), "type": type.rawValue])
    }

    public func searchSuggestions(query: String) async throws -> [String] {
        let response: SearchSuggestions = try await get("/api/v1/search/suggestions", query: ["q": query])
        return response.suggestions
    }

    // MARK: - Authenticated endpoints

    public func feed(page: Int = 1, maxResults: Int = 40) async throws -> FeedPage {
        try await get("/api/v1/auth/feed", query: ["page": String(page), "max_results": String(maxResults)])
    }

    public func subscriptions() async throws -> [SubscribedChannel] {
        try await get("/api/v1/auth/subscriptions")
    }

    public func subscribe(ucid: String) async throws {
        try await send("POST", "/api/v1/auth/subscriptions/\(ucid)")
    }

    public func unsubscribe(ucid: String) async throws {
        try await send("DELETE", "/api/v1/auth/subscriptions/\(ucid)")
    }

    /// Watched video IDs, newest first.
    public func history(page: Int = 1, maxResults: Int = 20) async throws -> [String] {
        try await get("/api/v1/auth/history", query: ["page": String(page), "max_results": String(maxResults)])
    }

    public func markWatched(videoID: String) async throws {
        try await send("POST", "/api/v1/auth/history/\(videoID)")
    }

    public func unmarkWatched(videoID: String) async throws {
        try await send("DELETE", "/api/v1/auth/history/\(videoID)")
    }

    public func clearHistory() async throws {
        try await send("DELETE", "/api/v1/auth/history")
    }

    // MARK: - Playlists

    /// The account's playlists. Each includes up to 100 videos.
    public func playlists() async throws -> [Playlist] {
        try await get("/api/v1/auth/playlists")
    }

    /// One playlist page (100 videos per page).
    public func playlist(id: String, page: Int = 1) async throws -> Playlist {
        try await get("/api/v1/auth/playlists/\(id)", query: ["page": String(page)])
    }

    /// Creates a playlist and returns its ID.
    public func createPlaylist(title: String, privacy: PlaylistPrivacy = .private) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["title": title, "privacy": privacy.rawValue])
        let (data, response) = try await sendJSON("POST", "/api/v1/auth/playlists", body: body)
        if let location = response.value(forHTTPHeaderField: "Location"), let id = location.split(separator: "/").last {
            return String(id)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = object["playlistId"] as? String {
            return id
        }
        throw InvidiousError.invalidResponse
    }

    public func deletePlaylist(id: String) async throws {
        try await send("DELETE", "/api/v1/auth/playlists/\(id)")
    }

    public func addVideo(_ videoID: String, toPlaylist playlistID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["videoId": videoID])
        _ = try await sendJSON("POST", "/api/v1/auth/playlists/\(playlistID)/videos", body: body)
    }

    /// Removes an entry by its `indexId`.
    public func removeVideo(indexId: String, fromPlaylist playlistID: String) async throws {
        try await send("DELETE", "/api/v1/auth/playlists/\(playlistID)/videos/\(indexId)")
    }

    /// Revokes the client's own access token on the server (token credentials only).
    public func unregisterToken() async throws {
        let body = try JSONSerialization.data(withJSONObject: [String: String]())
        _ = try await sendJSON("POST", "/api/v1/auth/tokens/unregister", body: body)
    }

    // MARK: - Login

    /// Signs in with username and password and returns the session ID.
    public func login(username: String, password: String) async throws -> String {
        let url = try absoluteURL("/login")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            ("email", username),
            ("password", password),
            ("action", "signin"),
        ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw InvidiousError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw InvidiousError.invalidResponse
        }
        switch http.statusCode {
        case 401:
            throw InvidiousError.invalidCredentials
        case 403:
            throw InvidiousError.loginDisabled
        case 200..<400:
            break
        default:
            throw InvidiousError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
        let cookies = http.allHeaderFieldsValues("Set-Cookie")
        guard let sid = Self.parseSID(fromSetCookieHeaders: cookies) else {
            // 200 without a cookie means the login page re-rendered with an error.
            throw InvidiousError.invalidCredentials
        }
        return sid
    }

    /// Extracts the `SID` cookie value from `Set-Cookie` headers.
    public static func parseSID(fromSetCookieHeaders headers: [String]) -> String? {
        for header in headers {
            for part in header.components(separatedBy: ";") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SID=") {
                    let value = String(trimmed.dropFirst(4))
                    return value.isEmpty ? nil : value
                }
            }
        }
        return nil
    }

    // MARK: - URL helpers

    /// Resolves an API-relative path such as `/vi/ID/maxres.jpg` against the instance.
    public func absoluteURL(_ path: String) throws -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            guard let url = URL(string: path) else { throw InvidiousError.invalidURL }
            return url
        }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw InvidiousError.invalidURL
        }
        return url
    }

    /// Absolute URL for a thumbnail, or nil when unresolvable.
    public func url(for thumbnail: Thumbnail) -> URL? {
        try? absoluteURL(thumbnail.url)
    }

    public func url(for image: AuthorImage) -> URL? {
        try? absoluteURL(image.url)
    }

    /// Absolute URL of a caption track in WebVTT.
    public func captionURL(_ caption: Caption) -> URL? {
        try? absoluteURL(caption.url)
    }

    // MARK: - Internals

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        let url = try makeURL(path, query: query)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(url: url))
        } catch {
            throw InvidiousError.network(error.localizedDescription)
        }
        try validate(response, data: data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw InvidiousError.decoding(String(describing: error))
        }
    }

    private func send(_ method: String, _ path: String) async throws {
        let url = try makeURL(path)
        var request = request(url: url)
        request.httpMethod = method
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw InvidiousError.network(error.localizedDescription)
        }
        try validate(response, data: data)
    }

    private func sendJSON(_ method: String, _ path: String, body: Data) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(path)
        var request = request(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw InvidiousError.network(error.localizedDescription)
        }
        try validate(response, data: data)
        guard let http = response as? HTTPURLResponse else { throw InvidiousError.invalidResponse }
        return (data, http)
    }

    private func makeURL(_ path: String, query: [String: String] = [:]) throws -> URL {
        var components = URLComponents(url: try absoluteURL(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw InvidiousError.invalidURL }
        return url
    }

    private func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch credential {
        case .sid(let sid)?:
            request.setValue("SID=\(sid)", forHTTPHeaderField: "Cookie")
        case .token(let token)?:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case nil:
            break
        }
        return request
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw InvidiousError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw InvidiousError.unauthorized
        default:
            throw InvidiousError.httpStatus(http.statusCode, Self.errorMessage(from: data))
        }
    }

    static func errorMessage(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? String {
            return error
        }
        return nil
    }

    static func formEncode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let body = fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

/// Stops URLSession from following redirects so the login response's cookies stay visible.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

extension HTTPURLResponse {
    /// All values of a header, splitting comma-joined `Set-Cookie` values back apart when safe.
    func allHeaderFieldsValues(_ name: String) -> [String] {
        guard let raw = value(forHTTPHeaderField: name) else { return [] }
        // URLSession joins repeated Set-Cookie headers with ", ". Cookie expiry dates also contain
        // ", " (e.g. "Sun, 03 Sep 2028") so split only where a new `key=` pair starts.
        var results: [String] = []
        var current = ""
        for piece in raw.components(separatedBy: ", ") {
            if current.isEmpty {
                current = piece
            } else if piece.range(of: #"^[A-Za-z0-9_\-]+="#, options: .regularExpression) != nil,
                      !piece.lowercased().hasPrefix("expires=") {
                results.append(current)
                current = piece
            } else {
                current += ", " + piece
            }
        }
        if !current.isEmpty { results.append(current) }
        return results
    }
}
