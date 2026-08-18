import Foundation
import Darwin
import DejavuDomain

public enum ClaudeStatusSnapshotProviderError: Error, Sendable, Equatable {
    case snapshotUnavailable
    case snapshotTooLarge
    case snapshotStale
    case invalidSnapshot
}

/// Reads only Dejavu's normalized Claude bridge snapshot. It never opens
/// Claude settings, Keychain items, transcripts, or browser data.
public struct ClaudeStatusSnapshotProvider: Sendable {
    public static let maximumSnapshotBytes = 256 * 1_024

    public let snapshotURL: URL
    public let freshnessPolicy: UsageFreshnessPolicy

    public init(
        snapshotURL: URL,
        freshnessPolicy: UsageFreshnessPolicy = UsageFreshnessPolicy()
    ) {
        self.snapshotURL = snapshotURL
        self.freshnessPolicy = freshnessPolicy
    }

    public func fetchUsage(now: Date = Date()) async throws -> ClaudeUsageSnapshot {
        let data: Data
        do {
            data = try Self.readSnapshot(at: snapshotURL)
        } catch let error as ClaudeStatusSnapshotProviderError {
            throw error
        } catch {
            throw ClaudeStatusSnapshotProviderError.snapshotUnavailable
        }

        let parsed: ClaudeUsageSnapshot
        do {
            parsed = try ClaudeStatusSnapshotParser().parse(data)
        } catch {
            throw ClaudeStatusSnapshotProviderError.invalidSnapshot
        }

        guard let fresh = freshnessPolicy.freshClaudeSnapshot(from: parsed, now: now) else {
            throw ClaudeStatusSnapshotProviderError.snapshotStale
        }
        return fresh
    }

    private static func readSnapshot(at url: URL) throws -> Data {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ClaudeStatusSnapshotProviderError.snapshotUnavailable
        }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_size > 0 else {
            throw ClaudeStatusSnapshotProviderError.snapshotUnavailable
        }
        guard information.st_size <= off_t(maximumSnapshotBytes) else {
            throw ClaudeStatusSnapshotProviderError.snapshotTooLarge
        }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw ClaudeStatusSnapshotProviderError.snapshotUnavailable
            }
            guard count > 0 else { return result }
            result.append(buffer, count: count)
            guard result.count <= maximumSnapshotBytes else {
                throw ClaudeStatusSnapshotProviderError.snapshotTooLarge
            }
        }
    }
}
