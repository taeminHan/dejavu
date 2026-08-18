import Foundation
import DejavuDomain

public enum DiagnosticsEventKind: String, Codable, CaseIterable, Sendable {
    case appStarted
    case refreshCompleted
    case localDataReset
}

public struct DiagnosticsEvent: Codable, Hashable, Sendable {
    public let recordedAt: Date
    public let kind: DiagnosticsEventKind
    public let status: UsageStatus?

    public init(recordedAt: Date, kind: DiagnosticsEventKind, status: UsageStatus? = nil) {
        self.recordedAt = recordedAt
        self.kind = kind
        self.status = status
    }
}

public enum DiagnosticsEventLogError: Error, Sendable, Equatable {
    case unsafeFile
    case eventTooLarge
    case fileSystemFailure
}

/// A bounded JSON-lines log containing only a closed event enum, timestamp,
/// and usage status. No caller-provided text can enter this file.
public actor DiagnosticsEventLog {
    public nonisolated let logURL: URL
    public nonisolated let previousLogURL: URL

    private let directoryURL: URL
    private let maximumBytes: Int

    public init(directoryURL: URL, maximumBytes: Int = 256 * 1_024) {
        self.directoryURL = directoryURL
        self.logURL = directoryURL.appendingPathComponent("diagnostics.log")
        self.previousLogURL = directoryURL.appendingPathComponent("diagnostics.previous.log")
        self.maximumBytes = max(1, maximumBytes)
    }

    public func append(_ event: DiagnosticsEvent) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(event)
        line.append(0x0A)
        guard line.count <= maximumBytes else { throw DiagnosticsEventLogError.eventTooLarge }

        do {
            try LocalDataDirectory.prepare(directoryURL)
            let fileManager = FileManager.default
            let currentSize = try safeFileSizeIfPresent(logURL)
            if currentSize + line.count > maximumBytes {
                if fileManager.fileExists(atPath: previousLogURL.path) {
                    try fileManager.removeItem(at: previousLogURL)
                }
                if fileManager.fileExists(atPath: logURL.path) {
                    try fileManager.moveItem(at: logURL, to: previousLogURL)
                    try setPrivatePermissions(previousLogURL)
                }
            }

            if fileManager.fileExists(atPath: logURL.path) {
                _ = try safeFileSizeIfPresent(logURL)
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.synchronize()
            } else {
                try line.write(to: logURL, options: .atomic)
            }
            try setPrivatePermissions(logURL)
        } catch let error as DiagnosticsEventLogError {
            throw error
        } catch {
            throw DiagnosticsEventLogError.fileSystemFailure
        }
    }

    private func safeFileSizeIfPresent(_ url: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            throw DiagnosticsEventLogError.unsafeFile
        }
        return size.intValue
    }

    private func setPrivatePermissions(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
