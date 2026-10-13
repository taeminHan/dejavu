import Darwin
import Foundation
import XCTest
import DejavuApplication
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
                requestTimeout: .seconds(2),
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
        let client = makeClient(transport: transport, configuration: CodexAppServerConfiguration(requestTimeout: .milliseconds(60)))
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
        # Reproduce startup slower than the old 150 ms test-only timeout.
        /bin/sleep 0.25
        printf '%s\n' "$$" > "${0}.pid"
        IFS= read -r initialize || exit 20
        printf '%s\n' '{"id":1,"result":{}}'
        IFS= read -r initialized || exit 21
        IFS= read -r account || exit 22
        printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}'
        IFS= read -r limits || exit 23
        printf '%s\n' 'ready' > "${0}.ready"
        while [ ! -f "${0}.release" ]; do /bin/sleep 0.01; done
        printf '%s\n' 'done' > "${0}.rotation-complete"
        printf '%s\n' '{"id":3,"result":{"rateLimits":{"secondary":{"usedPercent":34,"windowDurationMins":10080}}}}'
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
                // Cancellation must be tested after the request is pending,
                // not by racing cold process startup against an early timeout.
                requestTimeout: .seconds(15),
                shutdownGracePeriod: .milliseconds(100)
            )
        )
        let request = Task { try await client.fetchUsage() }
        let pidURL = URL(fileURLWithPath: executable.path + ".pid")
        let readyURL = URL(fileURLWithPath: executable.path + ".ready")
        let releaseURL = URL(fileURLWithPath: executable.path + ".release")
        let rotationURL = URL(fileURLWithPath: executable.path + ".rotation-complete")
        let startupDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: readyURL.path),
              ContinuousClock.now < startupDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard FileManager.default.fileExists(atPath: readyURL.path) else {
            request.cancel()
            try Data().write(to: releaseURL)
            await client.shutdown()
            XCTFail("Synthetic app-server did not reach the pending-read handshake")
            return
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: rotationURL.path))
        request.cancel()
        // Let the synthetic official client persist its in-band work and send
        // the response. The cancelled caller must discard it, then reap child.
        try Data().write(to: releaseURL)

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected. The blocking pipe read must have been unblocked.
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: rotationURL.path))

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
        let client = makeClient(transport: transport, configuration: CodexAppServerConfiguration(requestTimeout: .milliseconds(60)))
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

    func testBrowserLoginUsesOfficialFlowAndMatchingCompletion() async throws {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"synthetic-login","authUrl":"https://auth.openai.com/authorize?synthetic=1"}}"#.utf8),
            Data(#"{"method":"account/login/completed","params":{"loginId":"unrelated","success":false}}"#.utf8),
            Data(#"{"method":"account/login/completed","params":{"loginId":"synthetic-login","success":true,"error":null}}"#.utf8)
        ])
        let recorder = BrowserRecorder()
        try await makeClient(transport: transport).authenticate { await recorder.open($0) }
        let opened = await recorder.urls()
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(opened.first?.host, "auth.openai.com")
        let messages = await transport.sentMessages()
        try assertRequest(messages[2], method: "account/login/start", id: 2)
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: messages[2]) as? [String: Any])
        XCTAssertEqual((request["params"] as? [String: Any])?["type"] as? String, "chatgpt")
        let stopped = await transport.stopCount()
        XCTAssertEqual(stopped, 1)
    }

    func testBrowserLoginRejectsUntrustedURLWithoutOpeningBrowser() async throws {
        for url in ["https://example.com/signin", "file:///tmp/auth", "https://auth.openai.com.evil.example/", "https://user@auth.openai.com/"] {
            let response = try JSONSerialization.data(withJSONObject: ["id": 2, "result": ["type": "chatgpt", "loginId": "synthetic", "authUrl": url]])
            let transport = ScriptedCodexTransport(responses: [Data(#"{"id":1,"result":{}}"#.utf8), response])
            let recorder = BrowserRecorder()
            do {
                try await makeClient(transport: transport).authenticate { await recorder.open($0) }
                XCTFail("Expected invalid authentication URL")
            } catch {
                XCTAssertEqual(error as? CodexAppServerError, .invalidLoginResponse)
            }
            let opened = await recorder.urls()
            XCTAssertTrue(opened.isEmpty)
        }
    }

    func testLoginFailureDoesNotExposeProviderError() async throws {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"synthetic","authUrl":"https://auth.openai.com/authorize"}}"#.utf8),
            Data(#"{"method":"account/login/completed","params":{"loginId":"synthetic","success":false,"error":"private provider detail"}}"#.utf8)
        ])
        do {
            try await makeClient(transport: transport).authenticate { _ in }
            XCTFail("Expected login rejection")
        } catch { XCTAssertEqual(error as? CodexAppServerError, .loginRejected) }
    }

    func testRPCAuthBackendAndProtocolErrorsAreDistinct() async throws {
        let cases: [(Int, String, CodexAppServerError)] = [
            (-32600, "ChatGPT auth required", .loginRequired),
            (-32603, "backend 401 Unauthorized", .unauthorized),
            (-32603, "network unavailable", .backendFailed),
            (-32600, "Invalid request: auth protocol unsupported", .accountReadRejected)
        ]
        for (code, message, expected) in cases {
            let response = try JSONSerialization.data(withJSONObject: ["id": 2, "error": ["code": code, "message": message]])
            let transport = ScriptedCodexTransport(responses: [Data(#"{"id":1,"result":{}}"#.utf8), response])
            do {
                _ = try await makeClient(transport: transport).fetchUsage()
                XCTFail("Expected rejection")
            } catch { XCTAssertEqual(error as? CodexAppServerError, expected) }
        }
    }

    func testCancellationAllowsPendingReadToFinishBeforeTransportStops() async throws {
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"account":{"type":"chatgpt"},"requiresOpenaiAuth":true}}"#.utf8)
        ])
        let client = makeClient(transport: transport)
        let request = Task { try await client.fetchUsage() }
        while await transport.sentMessages().count < 4 { try await Task.sleep(for: .milliseconds(5)) }
        request.cancel()
        try await Task.sleep(for: .milliseconds(25))
        let stopsBeforeResponse = await transport.stopCount()
        XCTAssertEqual(stopsBeforeResponse, 0, "Do not interrupt an official token rotation")
        await transport.enqueue(try rateLimitsResponse(id: 3))
        do { _ = try await request.value; XCTFail("Cancelled read must publish no state") }
        catch is CancellationError { }
        let stopsAfterResponse = await transport.stopCount()
        XCTAssertEqual(stopsAfterResponse, 1)
    }

    func testLoginServiceReopensSameURLWithoutSecondServerAndClearsIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-auth-service-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let completedStopBarrier = SyntheticStopBarrier()
        let transport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"synthetic","authUrl":"https://auth.openai.com/authorize"}}"#.utf8)
        ], stopBarrier: completedStopBarrier)
        let service = CodexAuthenticationService(
            locator: CodexExecutableLocator(environment: ["CODEX_CLI_PATH": executable.path], homeDirectory: directory, systemBinaryDirectories: [], applicationDirectories: []),
            clientFactory: { url, config in CodexAppServerClient(executableURL: url, configuration: config, transportFactory: { _ in transport }) }
        )
        let recorder = BrowserRecorder()
        let first = Task { try await service.login { await recorder.open($0) } }
        while await recorder.urls().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let second = Task { try await service.login { await recorder.open($0) } }
        while await recorder.urls().count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        await transport.enqueue(Data(#"{"method":"account/login/completed","params":{"loginId":"synthetic","success":true}}"#.utf8))
        while await transport.stopCount() == 0 { try await Task.sleep(for: .milliseconds(5)) }
        _ = try await service.reopenBrowserIfPending { await recorder.open($0) }
        let openedAfterCompletion = await recorder.urls()
        XCTAssertEqual(openedAfterCompletion.count, 2, "A spent URL must be cleared before child cleanup completes")
        await completedStopBarrier.release()
        try await first.value
        try await second.value
        let starts = await transport.startCount()
        let active = await service.isAuthenticating
        XCTAssertEqual(starts, 1)
        XCTAssertFalse(active)
    }

    func testLoginTimeoutAndCancellationStopOwnedTransport() async throws {
        let responses = [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"synthetic","authUrl":"https://auth.openai.com/authorize"}}"#.utf8)
        ]
        let timedOut = ScriptedCodexTransport(responses: responses)
        let timeoutClient = makeClient(transport: timedOut, configuration: CodexAppServerConfiguration(loginTimeout: .milliseconds(40)))
        do { try await timeoutClient.authenticate { _ in }; XCTFail("Expected login timeout") }
        catch { XCTAssertEqual(error as? CodexAppServerError, .timedOut) }
        let timeoutStops = await timedOut.stopCount()
        XCTAssertEqual(timeoutStops, 1)

        let cancelled = ScriptedCodexTransport(responses: responses)
        let client = makeClient(transport: cancelled)
        let recorder = BrowserRecorder()
        let login = Task { try await client.authenticate { await recorder.open($0) } }
        while await recorder.urls().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        login.cancel()
        do { try await login.value; XCTFail("Expected login cancellation") }
        catch is CancellationError { }
        let cancellationStops = await cancelled.stopCount()
        XCTAssertEqual(cancellationStops, 1)
    }

    func testServiceCancelThenNewLoginWaitsForOldChildAndKeepsNewOperation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-auth-cancel-timeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let stopBarrier = SyntheticStopBarrier()
        let firstTransport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"first","authUrl":"https://auth.openai.com/authorize?attempt=first"}}"#.utf8)
        ], stopBarrier: stopBarrier)
        let nextTransport = ScriptedCodexTransport(responses: [
            Data(#"{"id":1,"result":{}}"#.utf8),
            Data(#"{"id":2,"result":{"type":"chatgpt","loginId":"next","authUrl":"https://auth.openai.com/authorize?attempt=next"}}"#.utf8)
        ])
        let queue = ScriptedTransportQueue([firstTransport, nextTransport])
        let service = CodexAuthenticationService(
            locator: CodexExecutableLocator(environment: ["CODEX_CLI_PATH": executable.path], homeDirectory: directory, systemBinaryDirectories: [], applicationDirectories: []),
            clientFactory: { url, config in
                let transport = queue.next()
                return CodexAppServerClient(executableURL: url, configuration: config, transportFactory: { _ in transport })
            }
        )
        let recorder = BrowserRecorder()
        let first = Task { try await service.login { await recorder.open($0) } }
        while await recorder.urls().isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        let cancel = Task { await service.cancel() }
        while await firstTransport.stopCount() == 0 { try await Task.sleep(for: .milliseconds(5)) }
        let next = Task { try await service.login { await recorder.open($0) } }
        try await Task.sleep(for: .milliseconds(30))
        let startsBeforeCleanup = await nextTransport.startCount()
        XCTAssertEqual(startsBeforeCleanup, 0, "A new login must await cancellation of the owned old child")
        let reopenedWhileCancelling = try await service.reopenBrowserIfPending { await recorder.open($0) }
        XCTAssertFalse(reopenedWhileCancelling, "A cancelled URL must not be reopened")
        await stopBarrier.release()
        await cancel.value
        do { try await first.value; XCTFail("Old login must remain cancelled") }
        catch is CancellationError { }
        while await recorder.urls().count < 2 { try await Task.sleep(for: .milliseconds(5)) }
        let stillAuthenticating = await service.isAuthenticating
        XCTAssertTrue(stillAuthenticating, "Old cleanup must never clear the new operation")
        let reopenedNext = try await service.reopenBrowserIfPending { await recorder.open($0) }
        XCTAssertTrue(reopenedNext)
        let opened = await recorder.urls()
        XCTAssertEqual(opened.count, 3)
        XCTAssertEqual(opened[1], opened[2])
        XCTAssertNotEqual(opened[0], opened[1])
        await nextTransport.enqueue(Data(#"{"method":"account/login/completed","params":{"loginId":"next","success":true}}"#.utf8))
        try await next.value
        let active = await service.isAuthenticating
        XCTAssertFalse(active)
    }

    func testServiceShutdownRejectsLaterLoginAndNeverReopensSpentURL() async throws {
        let service = CodexAuthenticationService()
        await service.shutdown()
        let recorder = BrowserRecorder()
        do { try await service.login { await recorder.open($0) }; XCTFail("Shutdown is permanent") }
        catch { XCTAssertEqual(error as? CodexAppServerError, .shutDown) }
        let reopened = try await service.reopenBrowserIfPending { await recorder.open($0) }
        let opened = await recorder.urls()
        XCTAssertFalse(reopened)
        XCTAssertTrue(opened.isEmpty)
    }

    func testProviderKeepsLoginRequiredOnTransientFailureButBackendAuthEvidenceClearsMissingAccount() async throws {
        let missingAccount = Data(#"{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}"#.utf8)
        let protocolFailure = Data(#"{"id":2,"error":{"code":-32600,"message":"Invalid request protocol"}}"#.utf8)
        let backend = Data(#"{"id":2,"error":{"code":-32603,"message":"Backend connection failed"}}"#.utf8)
        let (provider, directory) = try makeProvider(accountResponses: [missingAccount, protocolFailure, backend])
        defer { try? FileManager.default.removeItem(at: directory) }
        for expected: UsageProviderFailure in [.loginRequired, .loginRequired, .failed] {
            do { _ = try await provider.fetchUsage(); XCTFail("Expected provider failure") }
            catch { XCTAssertEqual(error as? UsageProviderFailure, expected) }
        }
    }

    func testProviderUnauthorizedRemainsStickyUntilExplicitLoginCompletion() async throws {
        let unauthorized = Data(#"{"id":2,"error":{"code":-32603,"message":"Backend 401 Unauthorized"}}"#.utf8)
        let backend = Data(#"{"id":2,"error":{"code":-32603,"message":"Backend connection failed"}}"#.utf8)
        let (provider, directory) = try makeProvider(accountResponses: [unauthorized, backend, backend])
        defer { try? FileManager.default.removeItem(at: directory) }
        for _ in 0..<2 {
            do { _ = try await provider.fetchUsage(); XCTFail("Expected login-required") }
            catch { XCTAssertEqual(error as? UsageProviderFailure, .loginRequired) }
        }
        await provider.authenticationCompleted()
        do { _ = try await provider.fetchUsage(); XCTFail("Expected transient backend failure") }
        catch { XCTAssertEqual(error as? UsageProviderFailure, .failed) }
    }

    private func makeProvider(accountResponses: [Data]) throws -> (CodexUsageProvider, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-provider-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let queue = ScriptedTransportQueue(accountResponses.map {
            ScriptedCodexTransport(responses: [Data(#"{"id":1,"result":{}}"#.utf8), $0])
        })
        let provider = CodexUsageProvider(
            locator: CodexExecutableLocator(environment: ["CODEX_CLI_PATH": executable.path], homeDirectory: directory, systemBinaryDirectories: [], applicationDirectories: []),
            configuration: CodexAppServerConfiguration(requestTimeout: .milliseconds(80)),
            clientFactory: { url, configuration in
                let transport = queue.next()
                return CodexAppServerClient(executableURL: url, configuration: configuration, transportFactory: { _ in transport })
            }
        )
        return (provider, directory)
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
    private let stopBarrier: SyntheticStopBarrier?

    init(responses: [Data], stopBarrier: SyntheticStopBarrier? = nil) {
        self.responses = responses
        self.stopBarrier = stopBarrier
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
            if !responses.isEmpty { return responses.removeFirst() }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CodexAppServerTransportError.endOfFile
    }

    func stop(gracePeriod: Duration) async {
        guard !stopped else { return }
        stopped = true
        stops += 1
        if let stopBarrier { await stopBarrier.wait() }
    }

    func sentMessages() -> [Data] { sent }
    func startCount() -> Int { starts }
    func stopCount() -> Int { stops }
    func enqueue(_ data: Data) { responses.append(data) }
}

private actor SyntheticStopBarrier {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor BrowserRecorder {
    private var opened: [URL] = []
    func open(_ url: URL) { opened.append(url) }
    func urls() -> [URL] { opened }
}

private final class ScriptedTransportQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [ScriptedCodexTransport]
    init(_ transports: [ScriptedCodexTransport]) { self.transports = transports }
    func next() -> ScriptedCodexTransport {
        lock.lock(); defer { lock.unlock() }
        return transports.removeFirst()
    }
}
