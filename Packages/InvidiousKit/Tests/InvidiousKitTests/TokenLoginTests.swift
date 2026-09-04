import Foundation
import Testing
@testable import InvidiousKit

@Suite("Token login")
struct TokenLoginTests {
    @Test func buildsAuthorizeURLWithScopesAndCallback() throws {
        let callback = try #require(TokenLogin.callbackURL(host: "192.168.1.20", port: 51234))
        #expect(callback.absoluteString == "http://192.168.1.20:51234/callback")
        let url = try #require(TokenLogin.authorizeURL(instance: URL(string: "http://192.168.1.10:3000")!, callback: callback))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "192.168.1.10")
        #expect(components.port == 3000)
        #expect(components.path == "/authorize_token")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["scopes"] == ":feed,:subscriptions*,:history*,:playlists*,POST:tokens/unregister")
        #expect(query["callback_url"] == "http://192.168.1.20:51234/callback")
    }

    @Test func parsesTheRedirectInvidiousSends() throws {
        // Invidious form-encodes the token JSON, then encodes it again as a query value.
        let tokenJSON = #"{"session":"v1:abc+def","scopes":[":feed"],"signature":"sig="}"#
        let formEncoded = tokenJSON
            .addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "*-._")))!
        var components = URLComponents(string: "http://192.168.1.20:51234/callback")!
        components.queryItems = [
            URLQueryItem(name: "token", value: formEncoded),
            URLQueryItem(name: "username", value: "leo%40example.com"),
        ]
        let result = try #require(TokenLogin.parseCallback(components.url!))
        #expect(result.token == formEncoded)
        #expect(result.username == "leo@example.com")
        #expect(result.credential == .token(formEncoded))
        // Decoding the token the way the server does yields the original JSON.
        #expect(result.token.removingPercentEncoding == tokenJSON)

        #expect(TokenLogin.parseCallback(URL(string: "http://h/callback?username=x")!) == nil)
        #expect(TokenLogin.parseCallback(URL(string: "http://h/other?token=x")!) == nil)
    }

    @Test func serverReceivesCallbackAndAnswersTheBrowser() async throws {
        let server = TokenCallbackServer()
        let port = try await server.start()
        #expect(port > 0)
        defer { server.stop() }

        let waiter = Task { try await server.waitForResult() }

        // Unknown paths do not resolve the wait.
        let session = URLSession(configuration: .ephemeral)
        let (_, notFound) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/favicon.ico")!)
        #expect((notFound as? HTTPURLResponse)?.statusCode == 404)

        let (body, response) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/callback?token=%257B%2522a%2522%253A1%257D&username=leo")!)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: body, as: UTF8.self).contains("Signed in"))

        let result = try await waiter.value
        #expect(result.token == "%7B%22a%22%3A1%7D")
        #expect(result.username == "leo")
    }

    @Test func stoppingTheServerFailsTheWait() async throws {
        let server = TokenCallbackServer()
        _ = try await server.start()
        let waiter = Task { try await server.waitForResult() }
        try await Task.sleep(for: .milliseconds(50))
        server.stop()
        await #expect(throws: TokenCallbackServer.ServerError.self) { try await waiter.value }
    }

    @Test func localAddressesSkipLoopback() {
        let addresses = LocalNetworkAddress.ipv4Addresses()
        #expect(!addresses.contains { $0.hasPrefix("127.") })
    }
}
