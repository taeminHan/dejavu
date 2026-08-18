import Foundation
import DejavuDomain

public struct ProviderDiagnostics: Codable, Hashable, Sendable {
    public let status: UsageStatus
    public let fiveHourPercent: Double?
    public let weeklyPercent: Double?
    public let capturedAt: Date?
    public let sourceAvailable: Bool

    public init(
        status: UsageStatus,
        fiveHourPercent: Double?,
        weeklyPercent: Double?,
        capturedAt: Date?,
        sourceAvailable: Bool
    ) {
        self.status = status
        self.fiveHourPercent = Self.safePercent(fiveHourPercent)
        self.weeklyPercent = Self.safePercent(weeklyPercent)
        self.capturedAt = capturedAt
        self.sourceAvailable = sourceAvailable
    }

    private static func safePercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return UsageLimit.clampedDisplayPercent(value)
    }
}

public struct WidgetDiagnostics: Codable, Hashable, Sendable {
    public let isVisible: Bool
    public let topLeftX: Double?
    public let topLeftY: Double?
    public let width: Double?
    public let height: Double?
    public let placement: WidgetPlacement
    public let backgroundOpacity: Double

    public init(
        isVisible: Bool,
        topLeftX: Double?,
        topLeftY: Double?,
        width: Double?,
        height: Double?,
        placement: WidgetPlacement,
        backgroundOpacity: Double
    ) {
        self.isVisible = isVisible
        self.topLeftX = Self.finite(topLeftX)
        self.topLeftY = Self.finite(topLeftY)
        self.width = Self.nonnegativeFinite(width)
        self.height = Self.nonnegativeFinite(height)
        self.placement = placement
        self.backgroundOpacity = backgroundOpacity.isFinite
            ? min(1, max(0, backgroundOpacity))
            : 1
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value = finite(value) else { return nil }
        return max(0, value)
    }
}

/// An allow-listed support snapshot. It intentionally has no message, path,
/// URL, account, request, credential, header, prompt, or conversation fields.
public struct DiagnosticsSnapshot: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let recordedAt: Date
    public let combinedStatus: UsageStatus
    public let updatedAt: Date?
    public let retryAt: Date?
    public let claude: ProviderDiagnostics
    public let codex: ProviderDiagnostics
    public let codexResetCredits: Int?
    public let widget: WidgetDiagnostics?

    public init(
        schemaVersion: Int = 1,
        recordedAt: Date,
        combinedStatus: UsageStatus,
        updatedAt: Date?,
        retryAt: Date?,
        claude: ProviderDiagnostics,
        codex: ProviderDiagnostics,
        codexResetCredits: Int?,
        widget: WidgetDiagnostics?
    ) {
        self.schemaVersion = schemaVersion
        self.recordedAt = recordedAt
        self.combinedStatus = combinedStatus
        self.updatedAt = updatedAt
        self.retryAt = retryAt
        self.claude = claude
        self.codex = codex
        self.codexResetCredits = codexResetCredits.map { max(0, $0) }
        self.widget = widget
    }

    public init(
        state: ApplicationState,
        recordedAt: Date = Date(),
        claudeSourceAvailable: Bool? = nil,
        codexSourceAvailable: Bool? = nil,
        widget: WidgetDiagnostics? = nil
    ) {
        self.init(
            recordedAt: recordedAt,
            combinedStatus: state.combinedStatus,
            updatedAt: state.updatedAt,
            retryAt: state.retryAt,
            claude: ProviderDiagnostics(
                status: state.claudeStatus,
                fiveHourPercent: state.claudeSnapshot?.fiveHour?.displayPercent,
                weeklyPercent: state.claudeSnapshot?.weekly?.displayPercent,
                capturedAt: state.claudeSnapshot?.capturedAt,
                sourceAvailable: claudeSourceAvailable ?? (state.claudeSnapshot != nil)
            ),
            codex: ProviderDiagnostics(
                status: state.codexStatus,
                // Keep the allow-listed field in the diagnostics schema so
                // older readers remain compatible, but Codex no longer
                // exposes a five-hour product metric.
                fiveHourPercent: nil,
                weeklyPercent: state.codexSnapshot?.weekly?.displayPercent,
                capturedAt: nil,
                sourceAvailable: codexSourceAvailable ?? (state.codexSnapshot != nil)
            ),
            codexResetCredits: state.codexSnapshot?.resetCredits,
            widget: widget
        )
    }
}

public actor DiagnosticsStore {
    public nonisolated let directoryURL: URL
    public nonisolated let statusURL: URL

    private let writer: any AtomicFileWriting

    public init(
        directoryURL: URL,
        writer: any AtomicFileWriting = FoundationAtomicFileWriter()
    ) {
        self.directoryURL = directoryURL
        self.statusURL = directoryURL.appendingPathComponent("status.json", isDirectory: false)
        self.writer = writer
    }

    public func write(_ snapshot: DiagnosticsSnapshot) throws {
        try LocalDataDirectory.prepare(directoryURL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writer.write(encoder.encode(snapshot), to: statusURL)
    }
}
