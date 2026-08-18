import XCTest
import DejavuDomain
@testable import DejavuPersistence

final class SettingsStoreTests: XCTestCase {
    func testMissingFileLoadsNormalizedDefaultsWithoutCreatingData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directoryURL: directory)

        let settings = await store.load()

        XCTAssertEqual(settings, AppSettings())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.settingsURL.path))
    }

    func testRoundTripUsesInjectedDirectoryAndStableStringEnums() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directoryURL: directory)
        let expected = AppSettings(
            primaryMetric: .weekly,
            showProgress: false,
            widgetOpacity: 0.72,
            customPosition: WidgetPosition(displayIdentifier: "display-1", topLeftX: 100, topLeftY: 80),
            backgroundColor: "#010203",
            accentColor: "#AABBCC",
            textColor: "#DDEEFF",
            useThresholdColors: false,
            refreshIntervalSeconds: 180,
            trayIconStyle: .percentage,
            widgetDensity: .comfortable,
            widgetLayout: .twoRows,
            serviceDisplayMode: .claudeAndCodex,
            widgetPlacement: .custom,
            appearance: .dark,
            firstRunCompleted: true,
            automaticUpdateChecksEnabled: false,
            lastNotifiedUpdateVersion: "1.2.3"
        )

        try await store.save(expected)
        let loaded = await store.load()
        let payload = try String(contentsOf: store.settingsURL, encoding: .utf8)

        XCTAssertEqual(loaded, expected)
        XCTAssertTrue(payload.contains("\"widgetDensity\" : \"comfortable\""))
        XCTAssertTrue(payload.contains("\"serviceDisplayMode\" : \"claudeAndCodex\""))
        XCTAssertFalse(store.settingsURL.path.contains("Library/Application Support"))
    }

    func testUnknownEnumsAndOutOfRangeNumbersAreRepairedWithoutCorruptBackup() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let raw = """
        {
          "primaryMetric": "futureMetric",
          "widgetDensity": "giant",
          "widgetLayout": "diagonal",
          "serviceDisplayMode": "everything",
          "widgetPlacement": "somewhere",
          "appearance": "neon",
          "widgetTheme": "futureTheme",
          "widgetOpacity": 9.5,
          "refreshIntervalSeconds": 1,
          "backgroundColor": "invalid",
          "accentColor": "#abcdef",
          "textColor": "#123456"
        }
        """
        try Data(raw.utf8).write(to: settingsURL)
        let store = SettingsStore(directoryURL: directory)

        let settings = await store.load()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        XCTAssertEqual(settings.primaryMetric, .fiveHour)
        XCTAssertEqual(settings.widgetDensity, .compact)
        XCTAssertEqual(settings.widgetLayout, .singleRow)
        XCTAssertEqual(settings.serviceDisplayMode, .autoDetect)
        XCTAssertEqual(settings.widgetPlacement, .bottomRight)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.widgetTheme, .modern)
        XCTAssertEqual(settings.widgetOpacity, 1)
        XCTAssertEqual(settings.refreshIntervalSeconds, 60)
        XCTAssertEqual(settings.backgroundColor, "#1E1E20")
        XCTAssertEqual(settings.accentColor, "#ABCDEF")
        XCTAssertTrue(files.contains("settings.json"))
        XCTAssertFalse(files.contains { $0.hasPrefix("settings.corrupt-") })
    }

    func testLegacyCodexFiveHourSelectionLoadsAndSavesAsWeekly() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        try Data(#"{"codexMenuBarMetric":"fiveHour"}"#.utf8).write(to: settingsURL)
        let store = SettingsStore(directoryURL: directory)

        let loaded = await store.load()
        try await store.save(AppSettings(codexMenuBarMetric: .fiveHour))
        let saved = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertEqual(loaded.codexMenuBarMetric, .weekly)
        XCTAssertTrue(saved.contains(#""codexMenuBarMetric" : "weekly""#))
        XCTAssertFalse(saved.contains(#""codexMenuBarMetric" : "fiveHour""#))
    }

    func testMalformedSettingsArePreservedAndDefaultsStillLoad() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        let corruptData = Data("{ definitely-not-json".utf8)
        try corruptData.write(to: settingsURL)
        let timestamp = Date(timeIntervalSince1970: 1_775_000_000)
        let store = SettingsStore(directoryURL: directory, now: { timestamp })

        let settings = await store.load()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let backup = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("settings.corrupt-") })

        XCTAssertEqual(settings, AppSettings())
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertEqual(try Data(contentsOf: backup), corruptData)
    }

    func testNonObjectJSONIsAlsoPreservedAsCorrupt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let settingsURL = directory.appendingPathComponent("settings.json")
        try Data("[]".utf8).write(to: settingsURL)
        let store = SettingsStore(directoryURL: directory)

        _ = await store.load()
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)

        XCTAssertFalse(files.contains("settings.json"))
        XCTAssertEqual(files.filter { $0.hasPrefix("settings.corrupt-") }.count, 1)
    }

    func testFailedAtomicWriteLeavesPreviousSettingsIntact() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workingStore = SettingsStore(directoryURL: directory)
        let original = AppSettings(refreshIntervalSeconds: 120)
        try await workingStore.save(original)
        let before = try Data(contentsOf: workingStore.settingsURL)
        let failingStore = SettingsStore(directoryURL: directory, writer: FailingWriter())

        do {
            try await failingStore.save(AppSettings(refreshIntervalSeconds: 240))
            XCTFail("Expected the injected writer to fail")
        } catch FailingWriter.ExpectedFailure.write {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(try Data(contentsOf: workingStore.settingsURL), before)
        let reloaded = await workingStore.load()
        XCTAssertEqual(reloaded, original)
    }

    func testSavedSettingsAndDirectoryUseOwnerOnlyPermissions() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(directoryURL: directory)

        try await store.save(AppSettings())

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.settingsURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-settings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private struct FailingWriter: AtomicFileWriting {
    enum ExpectedFailure: Error {
        case write
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        throw ExpectedFailure.write
    }
}
