import Foundation
import XCTest
@testable import DejavuProviders

final class ClaudeOAuthUsageClientTests: XCTestCase {
    func testTransientNetworkAndServerFailuresAreOffline() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransientFailureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for path in ["/timed-out", "/host-not-found", "/server-503"] {
            let client = ClaudeOAuthUsageClient(
                credentialReader: SyntheticCredentialReader(),
                session: session,
                endpoint: try XCTUnwrap(URL(string: "https://usage.invalid\(path)"))
            )

            do {
                _ = try await client.fetchUsage()
                XCTFail("Expected \(path) to fail")
            } catch let error as ClaudeExtendedUsageError {
                XCTAssertEqual(error, .offline, path)
            }
        }
    }
}

/// Returns a synthetic, unexpired credential envelope; no real Keychain item
/// is read.
private struct SyntheticCredentialReader: ClaudeCredentialReading {
    func readCredential() throws -> Data {
        Data(#"{"claudeAiOauth": {"accessToken": "synthetic"}}"#.utf8)
    }
}

/// Answers each request from its path only, so it keeps no shared state.
private final class TransientFailureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch url.path {
        case "/timed-out":
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        case "/host-not-found":
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
        default:
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 503,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
