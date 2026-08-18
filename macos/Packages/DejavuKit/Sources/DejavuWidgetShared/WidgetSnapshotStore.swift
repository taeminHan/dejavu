import Darwin
import Foundation

public enum WidgetSnapshotReadResult: Hashable, Sendable {
    case snapshot(WidgetUsageSnapshot)
    case missing
    case stale(lastUpdatedAt: Date)
    case invalid
    case unsupportedSchema(Int)
}

public struct WidgetSnapshotStore: Sendable {
    public let directoryURL: URL
    public let snapshotURL: URL
    public let maximumAge: TimeInterval
    public let maximumFutureClockSkew: TimeInterval

    public init(
        containerURL: URL,
        maximumAge: TimeInterval = WidgetConstants.snapshotMaximumAge,
        maximumFutureClockSkew: TimeInterval = 60
    ) {
        directoryURL = containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("DejavuWidget", isDirectory: true)
        snapshotURL = directoryURL.appendingPathComponent(
            WidgetConstants.snapshotFilename,
            isDirectory: false
        )
        self.maximumAge = Self.nonnegativeFinite(maximumAge)
        self.maximumFutureClockSkew = Self.nonnegativeFinite(maximumFutureClockSkew)
    }

    public static func appGroup(
        identifier: String = WidgetConstants.defaultAppGroupIdentifier,
        maximumAge: TimeInterval = WidgetConstants.snapshotMaximumAge
    ) -> Self? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            return nil
        }
        return Self(containerURL: containerURL, maximumAge: maximumAge)
    }

    /// The containing app is the only writer. Commit this snapshot before
    /// requesting a WidgetKit timeline reload.
    public func write(_ snapshot: WidgetUsageSnapshot) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: snapshotURL.path
        )
    }

    public func read(now: Date = Date()) -> WidgetSnapshotReadResult {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return .missing
        }

        do {
            let data = try Self.readSnapshot(at: snapshotURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let envelope = try decoder.decode(SchemaEnvelope.self, from: data)
            guard WidgetUsageSnapshot.supports(schemaVersion: envelope.schemaVersion) else {
                return .unsupportedSchema(envelope.schemaVersion)
            }

            let snapshot = try decoder.decode(WidgetUsageSnapshot.self, from: data)
            guard snapshot.updatedAt <= now.addingTimeInterval(maximumFutureClockSkew) else {
                return .invalid
            }
            guard now.timeIntervalSince(snapshot.updatedAt) <= maximumAge else {
                return .stale(lastUpdatedAt: snapshot.updatedAt)
            }
            return .snapshot(snapshot)
        } catch {
            return .invalid
        }
    }

    private static func nonnegativeFinite(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }

    private static func readSnapshot(at url: URL) throws -> Data {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw SnapshotReadError.invalid }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0,
              information.st_size <= off_t(WidgetConstants.maximumSnapshotBytes) else {
            throw SnapshotReadError.invalid
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw SnapshotReadError.invalid
            }
            guard count > 0 else { return result }
            result.append(buffer, count: count)
            guard result.count <= WidgetConstants.maximumSnapshotBytes else {
                throw SnapshotReadError.invalid
            }
        }
    }
}

private enum SnapshotReadError: Error {
    case invalid
}

private struct SchemaEnvelope: Decodable {
    let schemaVersion: Int
}
