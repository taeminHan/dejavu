import Darwin
import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class CodexAppServerClientTests: XCTestCase {
    func testDefaultProcessTransportUsesJSONLAndReapsItsChild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-codex-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("synthetic-codex")
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$$" > "${0}.pid"
        IFS= read -r initialize || exit 10
        printf '%s\n' '{"id":1,"result":{"platformFamily":"unix","platformOs":"macos"}}'
        IFS= read -r initialized || exit 11
        IFS= read -r account || exit 12
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"must-not-be-retained@example.com","planType":"plus"},"requiresOpenaiAuth":true}}'
        IFS= read -r limits || exit 13
        printf '%s\n' '{"id":3,"result":{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":null},"secondary":{"usedPercent":34,"windowDurationMins":10080,"resetsAt":null}}}}}'
        while IFS= read -r ignored; do :; done
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            configuration: CodexAppServerConfiguration(
                requestTimeout: .milliseconds(500),
                shutdownGracePeriod: .seconds(1)
            )
        )
        let snapshot = try await client.fetchUsage()

        XCTAssertEqual(snapshot.weekly?.percent, 34)
        let pidText = try String(
            contentsOf: URL(fileURLWithPath: executable.path + ".pid"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(pidText))
        XCTAssertEqual(Darwin.kill(pid, 0), -1, "Owned synthetic app-server must be reaped")
    }

    func testPerformsHandshakeThenReturnsParsedRateLimits() async throws {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"method":"account/updated","params":{}}"#.utf8),
            Data(#"{"id":99,"result":{}}"#.utf8),
            Data(#"{"id":1,"result":{"userAgent":"codex"}}"#.utf8),
            Data(#"{"id":2,"result":{"account":{"type":"chatgpt","email":"not-retained@example.com"},"requiresOpenaiAuth":true}}"#.utf8),
            Data(#"{"method":"account/rateLimits/updated","params":{}}"#.utf8),
            try rateLimitsResponse(id: 3)
        ])
        let client = makeClient(transport: transport)

        let snapshot = try await client.fetchUsage()

        XCTAssertEqual(snapshot.weekly?.percent, 40)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.resetCredits, 3)
        let messages = await transport.sentMessages()
        XCTAssertEqual(messages.count, 4)
        try assertRequest(messages[0], method: "initialize", id: 1)
        try assertClientInfo(messages[0])
        try assertNotification(messages[1], method: "initialized")
        try assertRequest(messages[2], method: "account/read", id: 2)
        try assertRefreshTokenDisabled(messages[2])
        try assertRequest(messages[3], method: "account/rateLimits/read", id: 3)
        let startCount = await transport.startCount()
        let stopCount = await transport.stopCount()
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func testMissingAuthenticatedAccountIsClassifiedAsLoginRequired() async throws {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{"userAgent":"codex"}}"#.utf8),
            Data(#"{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}"#.utf8)
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected login-required error")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .loginRequired)
        }

        let messages = await transport.sentMessages()
        XCTAssertEqual(messages.count, 3)
        try assertRequest(messages[2], method: "account/read", id: 2)
        let stopCount = await transport.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testInitializationErrorIsClassifiedWithoutRetainingServerDetails() async {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"error":{"code":-32000,"message":"private detail"}}"#.utf8)
        ])
        let client = makeClient(transport: transport)

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected initialization rejection")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .initializationRejected)
        }

        let sentCount = await transport.sentMessages().count
        let stopCount = await transport.stopCount()
        XCTAssertEqual(sentCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func testMalformedAndOversizedResponsesAreClassified() async throws {
        let malformed = ScriptedCodexTransport(responses: [Data("not-json".utf8)])
        let malformedClient = makeClient(transport: malformed)
        do {
            _ = try await malformedClient.fetchUsage()
            XCTFail("Expected malformed response")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .malformedResponse)
        }

        let oversized = ScriptedCodexTransport(responses: [Data(repeating: 0x78, count: 1_025)])
        let oversizedClient = makeClient(
            transport: oversized,
            configuration: CodexAppServerConfiguration(maximumLineBytes: 1_024)
        )
        do {
            _ = try await oversizedClient.fetchUsage()
            XCTFail("Expected oversized response")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .responseTooLarge)
        }
    }

    func testTimeoutStopsOwnedTransportAndReturnsPromptly() async {
        let transport = ScriptedCodexTransport(responses: [])
        let configuration = CodexAppServerConfiguration(
            requestTimeout: .milliseconds(25),
            shutdownGracePeriod: .zero
        )
        let client = makeClient(transport: transport, configuration: configuration)

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .timedOut)
        }

        let stopCount = await transport.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testCancellationStopsOwnedTransportAndRethrowsCancellation() async throws {
        let transport = ScriptedCodexTransport(responses: [])
        let client = makeClient(transport: transport)
        let request = Task { try await client.fetchUsage() }
        try await Task.sleep(for: .milliseconds(20))
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation is not translated to a provider failure.
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }

        let stopCount = await transport.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    func testDefaultProcessTransportCancellationUnblocksReadAndReapsChild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-codex-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("synthetic-codex")
        let script = #"""
        #!/bin/sh
        printf '%s\n' "$$" > "${0}.pid"
        IFS= read -r initialize || exit 20
        trap '' TERM
        while :; do :; done
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            configuration: CodexAppServerConfiguration(
                requestTimeout: .seconds(5),
                shutdownGracePeriod: .milliseconds(10)
            )
        )
        let request = Task { try await client.fetchUsage() }
        let pidURL = URL(fileURLWithPath: executable.path + ".pid")
        let startupDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !FileManager.default.fileExists(atPath: pidURL.path),
              ContinuousClock.now < startupDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard FileManager.default.fileExists(atPath: pidURL.path) else {
            request.cancel()
            await client.shutdown()
            XCTFail("Synthetic app-server did not start")
            return
        }
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected. The blocking pipe read must have been unblocked.
        }

        let pidText = try String(
            contentsOf: pidURL,
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let pid = try XCTUnwrap(pid_t(pidText))
        XCTAssertEqual(Darwin.kill(pid, 0), -1, "Cancelled app-server must be reaped")
    }

    func testShutdownRejectsFutureFetchWithoutStartingTransport() async {
        let transport = ScriptedCodexTransport(responses: [])
        let client = makeClient(transport: transport)
        await client.shutdown()

        do {
            _ = try await client.fetchUsage()
            XCTFail("Expected shutdown error")
        } catch {
            XCTAssertEqual(error as? CodexAppServerError, .shutDown)
        }

        let startCount = await transport.startCount()
        XCTAssertEqual(startCount, 0)
    }

    func testShutdownDuringRequestStopsTransportAndCancelsResult() async throws {
        let transport = ScriptedCodexTransport(responses: [])
        let client = makeClient(transport: transport)
        let request = Task { try await client.fetchUsage() }
        try await Task.sleep(for: .milliseconds(20))

        await client.shutdown()

        do {
            _ = try await request.value
            XCTFail("Expected shutdown cancellation")
        } catch is CancellationError {
            // Expected: shutdown cannot publish a late provider failure.
        } catch {
            XCTFail("Unexpected error: \(type(of: error))")
        }
        let stopCount = await transport.stopCount()
        XCTAssertEqual(stopCount, 1)
    }

    private func makeClient(
        transport: ScriptedCodexTransport,
        configuration: CodexAppServerConfiguration = CodexAppServerConfiguration()
    ) -> CodexAppServerClient {
        CodexAppServerClient(
            executableURL: URL(fileURLWithPath: "/synthetic/codex"),
            configuration: configuration,
            transportFactory: { _ in transport }
        )
    }

    private func rateLimitsResponse(id: Int) throws -> Data {
        let fixture = try FixtureSupport.data(named: "codex-exact-bucket.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture) as? [String: Any]
        )
        object["id"] = id
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func assertRequest(_ data: Data, method: String, id: Int) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["method"] as? String, method)
        XCTAssertEqual(object["id"] as? Int, id)
    }

    private func assertNotification(_ data: Data, method: String) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["method"] as? String, method)
        XCTAssertNil(object["id"])
        XCTAssertNotNil(object["params"] as? [String: Any])
    }

    private func assertClientInfo(_ data: Data) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["name"] as? String, "dejavu")
        XCTAssertEqual(clientInfo["title"] as? String, "Dejavu")
        XCTAssertEqual(clientInfo["version"] as? String, "0.1.0")
        XCTAssertNil(params["capabilities"])
    }

    private func assertRefreshTokenDisabled(_ data: Data) throws {
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        XCTAssertEqual(params["refreshToken"] as? Bool, false)
    }
}

private actor ScriptedCodexTransport: CodexAppServerTransport {
    private var responses: [Data]
    private var sent: [Data] = []
    private var starts = 0
    private var stops = 0
    private var stopped = false

    init(responses: [Data]) {
        self.responses = responses
    }

    func start() {
        starts += 1
    }

    func sendMessage(_ data: Data) {
        sent.append(data)
    }

    func receiveLine(maximumBytes: Int) async throws -> Data {
        if !responses.isEmpty {
            return responses.removeFirst()
        }

        while !stopped {
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CodexAppServerTransportError.endOfFile
    }

    func stop(gracePeriod: Duration) {
        guard !stopped else { return }
        stopped = true
        stops += 1
    }

    func sentMessages() -> [Data] { sent }
    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
}
