import DejavuDomain
import Foundation
import XCTest
@testable import DejavuWidgetShared

final class WidgetSnapshotStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DejavuWidgetSharedTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testRoundTripUsesOnlyAllowListedFieldsAndPrivatePermissions() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = WidgetSnapshotStore(containerURL: temporaryDirectory)
        let snapshot = WidgetUsageSnapshot(
            updatedAt: now,
            claude: WidgetClaudeSnapshot(
                status: .ready,
                fiveHourPercent: 38,
                weeklyPercent: 61,
                fablePercent: 12
            ),
            codex: WidgetCodexSnapshot(
                status: .ready,
                percent: 47
            )
        )

        try store.write(snapshot)

        XCTAssertEqual(store.read(now: now), .snapshot(snapshot))
        let text = try String(contentsOf: store.snapshotURL, encoding: .utf8)
        let lowercaseText = text.lowercased()
        for forbidden in [
            "token", "authorization", "credential", "account", "path", "plan",
            "resetcredit", "prompt", "conversation", "message", "url"
        ] {
            XCTAssertFalse(lowercaseText.contains(forbidden), "Unexpected field: \(forbidden)")
        }

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(object.keys),
            ["schemaVersion", "updatedAt", "claude", "codex"]
        )
        let claude = try XCTUnwrap(object["claude"] as? [String: Any])
        XCTAssertEqual(
            Set(claude.keys),
            ["status", "fiveHourPercent", "weeklyPercent", "fablePercent"]
        )
        let codex = try XCTUnwrap(object["codex"] as? [String: Any])
        XCTAssertEqual(Set(codex.keys), ["percent", "status"])

        let attributes = try FileManager.default.attributesOfItem(atPath: store.snapshotURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testProviderPercentagesAreClampedAndNonfiniteValuesBecomeMissing() {
        let claude = WidgetClaudeSnapshot(
            status: .ready,
            fiveHourPercent: -20,
            weeklyPercent: .nan
        )
        let upperBound = WidgetClaudeSnapshot(
            status: .ready,
            fiveHourPercent: 140,
            weeklyPercent: .infinity
        )
        let codex = WidgetCodexSnapshot(status: .ready, percent: 140)
        let missingCodex = WidgetCodexSnapshot(status: .ready, percent: .nan)

        XCTAssertEqual(claude.fiveHourPercent, 0)
        XCTAssertNil(claude.weeklyPercent)
        XCTAssertNil(claude.fablePercent)
        XCTAssertEqual(upperBound.fiveHourPercent, 100)
        XCTAssertNil(upperBound.weeklyPercent)
        XCTAssertEqual(codex.percent, 100)
        XCTAssertNil(missingCodex.percent)
    }

    func testLegacySchemaMapsOnlyCodexWeeklyPercent() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = WidgetSnapshotStore(containerURL: temporaryDirectory)
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        let legacy = #"""
        {
          "schemaVersion": 1,
          "updatedAt": "1970-01-01T02:46:40Z",
          "claude": {
            "status": "ready",
            "fiveHourPercent": 38,
            "weeklyPercent": 61,
            "fablePercent": 12
          },
          "codex": {
            "status": "ready",
            "fiveHourPercent": 22,
            "weeklyPercent": 47,
            "fablePercent": null
          }
        }
        """#
        try Data(legacy.utf8).write(to: store.snapshotURL)

        let expected = WidgetUsageSnapshot(
            updatedAt: now,
            claude: WidgetClaudeSnapshot(
                status: .ready,
                fiveHourPercent: 38,
                weeklyPercent: 61,
                fablePercent: 12
            ),
            codex: WidgetCodexSnapshot(status: .ready, percent: 47)
        )
        XCTAssertEqual(store.read(now: now), .snapshot(expected))

        let normalizedData = try JSONEncoder().encode(expected)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: normalizedData) as? [String: Any]
        )
        let codex = try XCTUnwrap(object["codex"] as? [String: Any])
        XCTAssertEqual(Set(codex.keys), ["percent", "status"])

        let shortWindowOnly = legacy.replacingOccurrences(
            of: #""weeklyPercent": 47"#,
            with: #""weeklyPercent": null"#
        )
        try Data(shortWindowOnly.utf8).write(to: store.snapshotURL, options: .atomic)
        guard case let .snapshot(shortWindowSnapshot) = store.read(now: now) else {
            XCTFail("Expected compatible legacy snapshot")
            return
        }
        XCTAssertNil(
            shortWindowSnapshot.codex?.percent,
            "Legacy Codex five-hour data must not replace a missing weekly value"
        )
    }

    func testMissingCorruptUnsupportedStaleAndFutureFilesAreDistinct() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = WidgetSnapshotStore(
            containerURL: temporaryDirectory,
            maximumAge: 300,
            maximumFutureClockSkew: 30
        )
        XCTAssertEqual(store.read(now: now), .missing)

        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: store.snapshotURL)
        XCTAssertEqual(store.read(now: now), .invalid)

        try Data("{\"schemaVersion\":99}".utf8).write(to: store.snapshotURL)
        XCTAssertEqual(store.read(now: now), .unsupportedSchema(99))

        let stale = WidgetUsageSnapshot(
            updatedAt: now.addingTimeInterval(-301),
            claude: nil,
            codex: nil
        )
        try store.write(stale)
        XCTAssertEqual(
            store.read(now: now),
            .stale(lastUpdatedAt: stale.updatedAt)
        )

        let future = WidgetUsageSnapshot(
            updatedAt: now.addingTimeInterval(31),
            claude: nil,
            codex: nil
        )
        try store.write(future)
        XCTAssertEqual(store.read(now: now), .invalid)
    }

    func testOversizedSnapshotIsRejectedBeforeDecoding() throws {
        let store = WidgetSnapshotStore(containerURL: temporaryDirectory)
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        let data = Data(
            repeating: 0x20,
            count: WidgetConstants.maximumSnapshotBytes + 1
        )
        try data.write(to: store.snapshotURL)

        XCTAssertEqual(store.read(), .invalid)
    }

    func testSymbolicLinkSnapshotIsRejected() throws {
        let store = WidgetSnapshotStore(containerURL: temporaryDirectory)
        try FileManager.default.createDirectory(
            at: store.directoryURL,
            withIntermediateDirectories: true
        )
        let target = store.directoryURL.appendingPathComponent("outside.json")
        try Data(#"{"schemaVersion":1}"#.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: store.snapshotURL,
            withDestinationURL: target
        )

        XCTAssertEqual(store.read(), .invalid)
    }

    func testApplicationStateInitializerCopiesNoMessagesOrResetCredits() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let state = ApplicationState(
            claudeStatus: .ready,
            claudeMessage: "private provider detail",
            claudeSnapshot: ClaudeUsageSnapshot(
                fiveHour: UsageLimit(percent: 35),
                weekly: nil,
                fable: UsageLimit(percent: 15),
                capturedAt: now
            ),
            codexStatus: .ready,
            codexMessage: "private app-server detail",
            codexSnapshot: CodexUsageSnapshot(
                weekly: UsageLimit(percent: 45),
                resetCredits: 99,
                resetCreditsExpireAt: now,
                planType: "private plan"
            ),
            updatedAt: now
        )

        let snapshot = WidgetUsageSnapshot(
            state: state,
            updatedAt: now,
            includesClaude: true,
            includesCodex: true
        )
        let data = try JSONEncoder().encode(snapshot)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertEqual(snapshot.claude?.fiveHourPercent, 35)
        XCTAssertEqual(snapshot.claude?.fablePercent, 15)
        XCTAssertEqual(snapshot.codex?.percent, 45)
        XCTAssertFalse(text.contains("private"))
        XCTAssertFalse(text.lowercased().contains("reset"))
        XCTAssertFalse(text.lowercased().contains("plan"))
    }
}
