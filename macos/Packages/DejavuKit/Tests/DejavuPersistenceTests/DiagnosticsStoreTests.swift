import XCTest
import DejavuDomain
@testable import DejavuPersistence

final class DiagnosticsStoreTests: XCTestCase {
    func testDiagnosticsAreAllowListedClampedAndContainNoStateMessages() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secret = "Bearer secret-token-from-provider"
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let state = ApplicationState(
            claudeStatus: .ready,
            claudeMessage: secret,
            claudeSnapshot: ClaudeUsageSnapshot(
                fiveHour: UsageLimit(percent: -20),
                weekly: UsageLimit(percent: 130),
                capturedAt: capturedAt
            ),
            codexStatus: .offline,
            codexMessage: "authorization header \(secret)",
            codexSnapshot: CodexUsageSnapshot(
                weekly: UsageLimit(percent: 45),
                resetCredits: -4,
                resetCreditsExpireAt: nil,
                planType: "sensitive-arbitrary-plan-string"
            ),
            updatedAt: capturedAt
        )
        let snapshot = DiagnosticsSnapshot(
            state: state,
            recordedAt: Date(timeIntervalSince1970: 2_000),
            widget: WidgetDiagnostics(
                isVisible: true,
                topLeftX: 10,
                topLeftY: 20,
                width: 300,
                height: 60,
                placement: .custom,
                backgroundOpacity: 2
            )
        )
        let store = DiagnosticsStore(directoryURL: directory)

        try await store.write(snapshot)
        let data = try Data(contentsOf: store.statusURL)
        let text = String(decoding: data, as: UTF8.self).lowercased()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticsSnapshot.self, from: data)

        XCTAssertFalse(text.contains(secret.lowercased()))
        XCTAssertFalse(text.contains("token"))
        XCTAssertFalse(text.contains("authorization"))
        XCTAssertFalse(text.contains("conversation"))
        XCTAssertFalse(text.contains("prompt"))
        XCTAssertFalse(text.contains("sensitive-arbitrary-plan-string"))
        XCTAssertEqual(decoded.claude.fiveHourPercent, 0)
        XCTAssertEqual(decoded.claude.weeklyPercent, 100)
        XCTAssertNil(decoded.codex.fiveHourPercent)
        XCTAssertEqual(decoded.codex.weeklyPercent, 45)
        XCTAssertEqual(decoded.codexResetCredits, 0)
        XCTAssertEqual(decoded.widget?.backgroundOpacity, 1)
    }

    func testDiagnosticsAtomicWriterFailureDoesNotReplaceExistingStatus() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workingStore = DiagnosticsStore(directoryURL: directory)
        let first = diagnostics(recordedAt: Date(timeIntervalSince1970: 1_000))
        try await workingStore.write(first)
        let originalData = try Data(contentsOf: workingStore.statusURL)
        let failingStore = DiagnosticsStore(directoryURL: directory, writer: DiagnosticsFailingWriter())

        do {
            try await failingStore.write(diagnostics(recordedAt: Date(timeIntervalSince1970: 2_000)))
            XCTFail("Expected the injected writer to fail")
        } catch DiagnosticsFailingWriter.ExpectedFailure.write {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: workingStore.statusURL), originalData)
    }

    func testInvalidGeometryIsRemovedBeforeEncoding() {
        let diagnostics = WidgetDiagnostics(
            isVisible: true,
            topLeftX: .nan,
            topLeftY: .infinity,
            width: -4,
            height: 20,
            placement: .topRight,
            backgroundOpacity: .nan
        )

        XCTAssertNil(diagnostics.topLeftX)
        XCTAssertNil(diagnostics.topLeftY)
        XCTAssertEqual(diagnostics.width, 0)
        XCTAssertEqual(diagnostics.height, 20)
        XCTAssertEqual(diagnostics.backgroundOpacity, 1)
    }

    private func diagnostics(recordedAt: Date) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            recordedAt: recordedAt,
            combinedStatus: .unavailable,
            updatedAt: nil,
            retryAt: nil,
            claude: ProviderDiagnostics(
                status: .unavailable,
                fiveHourPercent: nil,
                weeklyPercent: nil,
                capturedAt: nil,
                sourceAvailable: false
            ),
            codex: ProviderDiagnostics(
                status: .unavailable,
                fiveHourPercent: nil,
                weeklyPercent: nil,
                capturedAt: nil,
                sourceAvailable: false
            ),
            codexResetCredits: nil,
            widget: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private struct DiagnosticsFailingWriter: AtomicFileWriting {
    enum ExpectedFailure: Error {
        case write
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        throw ExpectedFailure.write
    }
}
