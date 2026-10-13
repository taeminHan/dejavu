import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class ClaudeOAuthUsageClientTests: XCTestCase {
    func testRateLimitClampsRetryAndAvoidsCredentialAndNetworkUntilExplicitRefresh() async throws {
        for (header, expectedDelay) in [("1", 60.0), ("999999", 1800.0), ("invalid", 60.0)] {
            let reader = SyntheticCredentialReader()
            let now = Date(timeIntervalSince1970: 2_000)
            let client = makeClient(reader: reader, endpointPath: "/rate-limit/" + header, now: now)
            for _ in 0..<2 {
                do { _ = try await client.fetchUsage(); XCTFail("Expected rate limit") }
                catch let ClaudeExtendedUsageError.rateLimited(retryAt) {
                    XCTAssertEqual(try XCTUnwrap(retryAt).timeIntervalSince(now), expectedDelay, accuracy: 0.1)
                }
            }
            XCTAssertEqual(reader.readCount(), 1, "Backoff must not repeatedly prompt Keychain")
            await client.resetRetryBackoff()
            do { _ = try await client.fetchUsage(); XCTFail("Expected another rate limit") }
            catch ClaudeExtendedUsageError.rateLimited(_) { }
            XCTAssertEqual(reader.readCount(), 2, "Explicit refresh may try once")
        }
    }

    func testExpiredAccessTokenWithUsableRefreshTokenIsNotLoginRequired() async throws {
        let cases: [(String, ClaudeExtendedUsageError)] = [
            (#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":1000,"refreshToken":"synthetic-refresh"}}"#, .tokenRefreshPending),
            (#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":1000}}"#, .credentialExpired),
            (#"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":1000,"refreshToken":"synthetic-refresh","refreshTokenExpiresAt":1000}}"#, .credentialExpired)
        ]
        for (json, expected) in cases {
            let client = makeClient(reader: SyntheticCredentialReader(data: Data(json.utf8)), endpointPath: "/must-not-request", now: Date(timeIntervalSince1970: 2_000))
            do { _ = try await client.fetchUsage(); XCTFail("Expected credential state") }
            catch { XCTAssertEqual(error as? ClaudeExtendedUsageError, expected) }
        }
    }

    func testTimeoutIsOfflineInsteadOfMalformedResponse() async throws {
        let client = makeClient(reader: SyntheticCredentialReader(), endpointPath: "/timeout", now: Date())
        do { _ = try await client.fetchUsage(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? ClaudeExtendedUsageError, .offline) }
    }

    func testServerFailureIsDistinctFromChangedEndpointOrInvalidPayload() async throws {
        let cases: [(String, ClaudeExtendedUsageError)] = [("/status/503", .serverError), ("/status/404", .invalidResponse), ("/status/200", .invalidResponse)]
        for (path, expected) in cases {
            let client = makeClient(reader: SyntheticCredentialReader(), endpointPath: path, now: Date())
            do { _ = try await client.fetchUsage(); XCTFail("Expected classified HTTP error") }
            catch { XCTAssertEqual(error as? ClaudeExtendedUsageError, expected) }
        }
    }

    func testIdentityChangeDiscardsLateSuccessErrorsAndRateLimitWithoutContaminatingNewIdentity() async throws {
        let cases: [Result<(Data, URLResponse), Error>] = [
            SyntheticIdentityTransport.response(status: 200, body: #"{"five_hour":{"utilization":17}}"#),
            SyntheticIdentityTransport.response(status: 429, body: "{}", headers: ["Retry-After": "1800"]),
            SyntheticIdentityTransport.response(status: 503, body: "{}"),
            SyntheticIdentityTransport.response(status: 200, body: "not-json"),
            .failure(URLError(.timedOut))
        ]
        for oldResult in cases {
            let started = XCTestExpectation(description: "Synthetic old identity request started")
            let transport = SyntheticIdentityTransport(onFirstRequest: { started.fulfill() })
            let factory = SyntheticIdentityReaderFactory()
            let client = ClaudeOAuthUsageClient(credentialReaderFactory: factory.reader, requestOperation: transport.request)
            let oldFetch = Task { try await client.fetchUsage() }
            let waitResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
            guard waitResult == .completed else {
                await transport.releaseFirst(.failure(CancellationError()))
                oldFetch.cancel()
                _ = try? await oldFetch.value
                XCTFail("Synthetic request did not start")
                continue
            }

            await client.setCredentialIdentity(.previousDejavuDefault)
            await transport.releaseFirst(oldResult)
            do { _ = try await oldFetch.value; XCTFail("Old identity must not publish a result") }
            catch { XCTAssertTrue(error is CancellationError) }

            let snapshot = try await client.fetchUsage()
            let selectedIdentity = await client.currentCredentialIdentity
            let requestCount = await transport.callCount()
            let cancellationObserved = await transport.firstRequestWasCancelled
            XCTAssertEqual(selectedIdentity, .previousDejavuDefault)
            XCTAssertEqual(snapshot.fiveHour?.percent, 71)
            XCTAssertEqual(snapshot.source, .oauthUsage)
            XCTAssertEqual(factory.requestedIdentities(), [.standard, .previousDejavuDefault])
            XCTAssertEqual(requestCount, 2, "Late 429 must not impose the old identity's backoff")
            XCTAssertTrue(cancellationObserved, "Only the owned old request must be cancelled")
        }
    }

    func testIdentityChangeResetsExistingBackoffAndDoesNotReadCredentialsUntilFetch() async throws {
        let factory = SyntheticIdentityReaderFactory()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticClaudeURLProtocol.self]
        let client = ClaudeOAuthUsageClient(
            credentialReaderFactory: factory.reader,
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://synthetic.invalid/rate-limit/1800")!
        )
        do { _ = try await client.fetchUsage(); XCTFail("Expected initial backoff") }
        catch ClaudeExtendedUsageError.rateLimited(_) { }
        await client.setCredentialIdentity(.previousDejavuDefault)
        XCTAssertEqual(factory.requestedIdentities(), [.standard], "Changing selection alone must not open Keychain")
        do { _ = try await client.fetchUsage(); XCTFail("Expected new identity's one request") }
        catch ClaudeExtendedUsageError.rateLimited(_) { }
        XCTAssertEqual(factory.requestedIdentities(), [.standard, .previousDejavuDefault])
    }

    func testCancelledConfigurationTaskCannotOverwriteNewerSelectedIdentity() async {
        let factory = SyntheticIdentityReaderFactory()
        let transport = SyntheticIdentityTransport(onFirstRequest: {})
        let client = ClaudeOAuthUsageClient(credentialReaderFactory: factory.reader, requestOperation: transport.request)
        await client.setCredentialIdentity(.previousDejavuDefault)
        let oldConfiguration = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await client.setCredentialIdentity(.standard)
        }
        await oldConfiguration.value
        let selectedIdentity = await client.currentCredentialIdentity
        let count = await transport.callCount()
        XCTAssertEqual(selectedIdentity, .previousDejavuDefault)
        XCTAssertEqual(factory.requestedIdentities(), [])
        XCTAssertEqual(count, 0)
    }

    func testInjectedFixedReaderRemainsSyntheticAfterIdentityChange() async throws {
        let reader = SyntheticCredentialReader()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticClaudeURLProtocol.self]
        let client = ClaudeOAuthUsageClient(
            credentialReader: reader,
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://synthetic.invalid/status/503")!
        )
        for identity in ClaudeCredentialIdentity.allCases {
            await client.setCredentialIdentity(identity)
            do { _ = try await client.fetchUsage(); XCTFail("Expected synthetic server failure") }
            catch { XCTAssertEqual(error as? ClaudeExtendedUsageError, .serverError) }
        }
        XCTAssertEqual(reader.readCount(), 2)
    }

    func testCancelledFetchDiscardsLateTransportSuccessWithoutIdentityChange() async throws {
        let started = XCTestExpectation(description: "Synthetic cancellable request started")
        let transport = SyntheticIdentityTransport(onFirstRequest: { started.fulfill() })
        let factory = SyntheticIdentityReaderFactory()
        let client = ClaudeOAuthUsageClient(credentialReaderFactory: factory.reader, requestOperation: transport.request)
        let fetch = Task { try await client.fetchUsage() }
        let waitResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        fetch.cancel()
        await transport.releaseFirst(SyntheticIdentityTransport.response(status: 200, body: #"{"five_hour":{"utilization":17}}"#))
        do { _ = try await fetch.value; XCTFail("Cancelled request must not publish a result") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(waitResult, .completed)
    }

    private func makeClient(reader: SyntheticCredentialReader, endpointPath: String, now: Date) -> ClaudeOAuthUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticClaudeURLProtocol.self]
        return ClaudeOAuthUsageClient(
            credentialReader: reader,
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://synthetic.invalid" + endpointPath)!,
            now: { now }
        )
    }
}

private final class SyntheticIdentityReaderFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let standard = SyntheticCredentialReader()
    private let previous = SyntheticCredentialReader()
    private var identities: [ClaudeCredentialIdentity] = []

    func reader(identity: ClaudeCredentialIdentity) -> any ClaudeCredentialReading {
        lock.lock()
        defer { lock.unlock() }
        identities.append(identity)
        return identity == .standard ? standard : previous
    }

    func requestedIdentities() -> [ClaudeCredentialIdentity] {
        lock.lock()
        defer { lock.unlock() }
        return identities
    }
}

private actor SyntheticIdentityTransport {
    private let onFirstRequest: @Sendable () -> Void
    private var firstContinuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var firstResult: Result<(Data, URLResponse), Error>?
    private var calls = 0
    private(set) var firstRequestWasCancelled = false

    init(onFirstRequest: @escaping @Sendable () -> Void) { self.onFirstRequest = onFirstRequest }

    func request(_ request: URLRequest) async throws -> (Data, URLResponse) {
        calls += 1
        if calls != 1 {
            return try Self.response(status: 200, body: #"{"five_hour":{"utilization":71}}"#).get()
        }
        onFirstRequest()
        // Deliberately ignores cancellation until released. This proves the
        // generation barrier, not merely URLSession's cooperative cancellation.
        do {
            let value: (Data, URLResponse)
            if let firstResult { value = try firstResult.get() }
            else { value = try await withCheckedThrowingContinuation { firstContinuation = $0 } }
            firstRequestWasCancelled = Task.isCancelled
            return value
        } catch {
            firstRequestWasCancelled = Task.isCancelled
            throw error
        }
    }

    func releaseFirst(_ result: Result<(Data, URLResponse), Error>) {
        firstResult = result
        firstContinuation?.resume(with: result)
        firstContinuation = nil
    }

    func callCount() -> Int { calls }

    nonisolated static func response(status: Int, body: String, headers: [String: String] = [:]) -> Result<(Data, URLResponse), Error> {
        let response = HTTPURLResponse(url: URL(string: "https://synthetic.invalid/usage")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return .success((Data(body.utf8), response))
    }
}

private final class SyntheticCredentialReader: ClaudeCredentialReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let data: Data
    init(data: Data = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-test-only"}}"#.utf8)) { self.data = data }
    func readCredential() throws -> Data { lock.lock(); defer { lock.unlock() }; count += 1; return data }
    func readCount() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}

private final class SyntheticClaudeURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        if url.path.hasPrefix("/status/"), let status = Int(url.lastPathComponent) {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("not-a-valid-usage-payload".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": url.lastPathComponent])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
