import XCTest
@testable import DejavuDomain

final class AppSettingsTests: XCTestCase {
    func testNormalizationClampsNumbersColorsAndVersion() {
        var settings = AppSettings()
        settings.widgetOpacity = 4
        settings.refreshIntervalSeconds = 5
        settings.backgroundColor = "not-a-color"
        settings.accentColor = " #abcdef "
        settings.textColor = "#11223344"
        settings.lastNotifiedUpdateVersion = "  \(String(repeating: "v", count: 80))  "

        settings.normalize()

        XCTAssertEqual(settings.widgetOpacity, 1)
        XCTAssertEqual(settings.refreshIntervalSeconds, 60)
        XCTAssertEqual(settings.backgroundColor, "#1E1E20")
        XCTAssertEqual(settings.accentColor, "#ABCDEF")
        XCTAssertEqual(settings.textColor, "#11223344")
        XCTAssertEqual(settings.lastNotifiedUpdateVersion?.count, 64)
    }

    func testAllPersistedEnumsEncodeAsStableEnglishStrings() throws {
        let settings = AppSettings(
            primaryMetric: .weekly,
            claudeMenuBarMetric: .weekly,
            codexMenuBarMetric: .hidden,
            trayIconStyle: .percentage,
            widgetDensity: .comfortable,
            widgetLayout: .twoRows,
            serviceDisplayMode: .claudeAndCodex,
            widgetPlacement: .custom,
            appearance: .dark,
            widgetTheme: .modern
        )
        let data = try JSONEncoder().encode(settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["primaryMetric"] as? String, "weekly")
        XCTAssertEqual(json["claudeMenuBarMetric"] as? String, "weekly")
        XCTAssertEqual(json["codexMenuBarMetric"] as? String, "hidden")
        XCTAssertEqual(json["claudeMenuBarMetrics"] as? [String], ["weekly"])
        XCTAssertEqual(json["showsCodexInMenuBar"] as? Bool, false)
        XCTAssertEqual(json["trayIconStyle"] as? String, "percentage")
        XCTAssertEqual(json["widgetDensity"] as? String, "comfortable")
        XCTAssertEqual(json["widgetLayout"] as? String, "twoRows")
        XCTAssertEqual(json["serviceDisplayMode"] as? String, "claudeAndCodex")
        XCTAssertEqual(json["widgetPlacement"] as? String, "custom")
        XCTAssertEqual(json["appearance"] as? String, "dark")
        XCTAssertEqual(json["widgetTheme"] as? String, "modern")
    }

    func testMenuBarMetricHasStableCompleteCaseSet() {
        XCTAssertEqual(MenuBarMetric.allCases, [.fiveHour, .weekly, .fable, .hidden])
        XCTAssertEqual(MenuBarMetric.fiveHour.rawValue, "fiveHour")
        XCTAssertEqual(MenuBarMetric.weekly.rawValue, "weekly")
        XCTAssertEqual(MenuBarMetric.fable.rawValue, "fable")
        XCTAssertEqual(MenuBarMetric.hidden.rawValue, "hidden")
    }

    func testMenuBarMetricsRoundTrip() throws {
        let expected = AppSettings(
            claudeMenuBarMetric: .hidden,
            codexMenuBarMetric: .weekly,
            showsWidget: false,
            extendedFableAccessEnabled: true
        )

        let data = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.claudeMenuBarMetric, .hidden)
        XCTAssertEqual(decoded.codexMenuBarMetric, .weekly)
        XCTAssertFalse(decoded.showsWidget)
        XCTAssertTrue(decoded.extendedFableAccessEnabled)
        XCTAssertEqual(decoded, expected)
    }

    func testUnsupportedCodexMetricsRepairToWeekly() throws {
        let data = Data(#"{"codexMenuBarMetric":"fiveHour"}"#.utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.codexMenuBarMetric, .weekly)
        XCTAssertEqual(AppSettings(codexMenuBarMetric: .fiveHour).codexMenuBarMetric, .weekly)
        XCTAssertEqual(AppSettings(codexMenuBarMetric: .fable).codexMenuBarMetric, .weekly)
    }

    func testClaudeFableMenuBarMetricRoundTrips() throws {
        let expected = AppSettings(
            claudeMenuBarMetrics: [.fiveHour, .weekly, .fable],
            showsCodexInMenuBar: false,
            extendedFableAccessEnabled: true
        )

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded.claudeMenuBarMetrics, [.fiveHour, .weekly, .fable])
        XCTAssertFalse(decoded.showsCodexInMenuBar)
        XCTAssertTrue(decoded.extendedFableAccessEnabled)
    }

    func testLegacySingleMenuBarSelectionsMigrateToIndependentVisibility() throws {
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(
                #"{"claudeMenuBarMetric":"fable","codexMenuBarMetric":"hidden"}"#.utf8
            )
        )

        XCTAssertEqual(decoded.claudeMenuBarMetrics, [.fable])
        XCTAssertFalse(decoded.showsCodexInMenuBar)
    }

    func testDuplicateHiddenAndUnorderedSelectionsNormalizeCanonically() {
        let settings = AppSettings(
            claudeMenuBarMetrics: [.fable, .hidden, .fiveHour, .fable, .weekly]
        )

        XCTAssertEqual(settings.claudeMenuBarMetrics, [.fiveHour, .weekly, .fable])
        XCTAssertEqual(settings.claudeMenuBarMetric, .fiveHour)
    }

    func testMissingMenuBarMetricFieldsUseProviderSpecificDefaults() throws {
        let data = Data("{\"schemaVersion\":1}".utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.claudeMenuBarMetric, .fiveHour)
        XCTAssertEqual(decoded.codexMenuBarMetric, .weekly)
        XCTAssertTrue(decoded.showsWidget)
        XCTAssertFalse(decoded.extendedFableAccessEnabled)
    }

    func testUnknownMenuBarMetricValuesUseProviderSpecificDefaults() throws {
        let data = Data(
            "{\"claudeMenuBarMetric\":\"futureClaudeMetric\","
                .appending("\"codexMenuBarMetric\":\"futureCodexMetric\"}")
                .utf8
        )

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.claudeMenuBarMetric, .fiveHour)
        XCTAssertEqual(decoded.codexMenuBarMetric, .weekly)
    }

    func testInvalidShowsWidgetValueUsesTrueDefault() throws {
        let data = Data("{\"showsWidget\":\"sometimes\"}".utf8)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.showsWidget)
    }
}
