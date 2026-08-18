import Foundation
import DejavuDomain

public actor SettingsStore {
    public nonisolated let directoryURL: URL
    public nonisolated let settingsURL: URL

    private let writer: any AtomicFileWriting
    private let now: @Sendable () -> Date

    public init(
        directoryURL: URL,
        writer: any AtomicFileWriting = FoundationAtomicFileWriter(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directoryURL = directoryURL
        self.settingsURL = directoryURL.appendingPathComponent("settings.json", isDirectory: false)
        self.writer = writer
        self.now = now
    }

    public func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)
            settings.normalize()
            return settings
        } catch {
            preserveCorruptSettingsIfPossible()
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        try LocalDataDirectory.prepare(directoryURL)

        let normalized = settings.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalized)
        try writer.write(data, to: settingsURL)
    }

    private func preserveCorruptSettingsIfPossible() {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }

        do {
            try LocalDataDirectory.prepare(directoryURL)
            let baseName = "settings.corrupt-\(corruptTimestamp(now()))"
            var backupURL = directoryURL.appendingPathComponent("\(baseName).json", isDirectory: false)
            var suffix = 1
            while FileManager.default.fileExists(atPath: backupURL.path) {
                backupURL = directoryURL.appendingPathComponent(
                    "\(baseName)-\(suffix).json",
                    isDirectory: false
                )
                suffix += 1
            }
            try FileManager.default.moveItem(at: settingsURL, to: backupURL)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: backupURL.path
            )
        } catch {
            // A read-only or locked file must not prevent startup with defaults.
        }
    }

    private func corruptTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
