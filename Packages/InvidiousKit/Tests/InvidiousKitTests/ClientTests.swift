import Foundation
import Testing
@testable import InvidiousKit

@Suite("Client helpers")
struct ClientTests {
    let client = InvidiousClient(baseURL: URL(string: "http://192.168.1.10:3000")!)

    @Test func parsesSIDCookie() {
        let headers = ["SID=abc123==; expires=Sun, 03 Sep 2028 21:48:59 GMT; HttpOnly; SameSite=Lax"]
        #expect(InvidiousClient.parseSID(fromSetCookieHeaders: headers) == "abc123==")
        #expect(InvidiousClient.parseSID(fromSetCookieHeaders: ["PREFS=x; Path=/"]) == nil)
        #expect(InvidiousClient.parseSID(fromSetCookieHeaders: []) == nil)
    }

    @Test func splitsJoinedSetCookieHeaders() throws {
        let url = URL(string: "http://example.com/login")!
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: [
            "Set-Cookie": "PREFS=abc; expires=Sun, 03 Sep 2028 21:48:59 GMT; Path=/, SID=xyz; expires=Sun, 03 Sep 2028 21:48:59 GMT; HttpOnly",
        ])!
        let cookies = response.allHeaderFieldsValues("Set-Cookie")
        #expect(cookies.count == 2)
        #expect(InvidiousClient.parseSID(fromSetCookieHeaders: cookies) == "xyz")
    }

    @Test func resolvesRelativeAndAbsoluteURLs() throws {
        #expect(try client.absoluteURL("/vi/abc/maxres.jpg").absoluteString == "http://192.168.1.10:3000/vi/abc/maxres.jpg")
        #expect(try client.absoluteURL("https://i.ytimg.com/x.jpg").absoluteString == "https://i.ytimg.com/x.jpg")
    }

    @Test func formEncodesCredentials() {
        let body = InvidiousClient.formEncode([("email", "ada lovelace"), ("password", "a&b=c")])
        #expect(String(decoding: body, as: UTF8.self) == "email=ada%20lovelace&password=a%26b%3Dc")
    }

    @Test func authenticatedCopyKeepsBaseURL() {
        let auth = client.authenticated(sid: "s")
        #expect(auth.sid == "s")
        #expect(auth.baseURL == client.baseURL)
    }
}
