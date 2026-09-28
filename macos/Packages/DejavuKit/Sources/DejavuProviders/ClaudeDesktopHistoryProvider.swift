import Foundation
import Darwin
import DejavuDomain

public enum ClaudeDesktopHistoryProviderError: Error, Sendable, Equatable {
    case historyUnavailable
    case historyTooLarge
    case historyStale
    case invalidHistory
}

public enum ClaudeDesktopHistoryParserError: Error, Sendable, Equatable {
    case noUsableSample
}

/// Decodes Claude Desktop's local `plan-usage-history.json`.
///
/// Only each sample's capture time (`t`, epoch milliseconds) and its 5-hour
/// (`u.fh`) and seven-day (`u.sd`) percentages are modeled. The organization
/// field and every other usage key are never decoded. A malformed sample is
/// skipped instead of rejecting the whole history, and the latest sample by
/// capture time wins even when the file is not ordered, matching the Windows
/// `ClaudeDesktopUsageReader`.
public struct ClaudeDesktopHistoryParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> ClaudeUsageSnapshot {
        let payload = try JSONDecoder().decode(HistoryPayload.self, from: data)

        var latest: (timestamp: Int64, usage: HistoryUsage)?
        for sample in payload.samples {
            guard let timestamp = sample.timestamp, let usage = sample.usage else { continue }
            if let current = latest, timestamp <= current.timestamp { continue }
            latest = (timestamp, usage)
        }

        guard let selected = latest,
              selected.usage.fiveHour != nil || selected.usage.sevenDay != nil else {
            throw ClaudeDesktopHistoryParserError.noUsableSample
        }

        return ClaudeUsageSnapshot(
            fiveHour: selected.usage.fiveHour.map { UsageLimit(percent: $0) },
            weekly: selected.usage.sevenDay.map { UsageLimit(percent: $0) },
            fable: nil,
            source: .desktopHistory,
            capturedAt: Date(timeIntervalSince1970: TimeInterval(selected.timestamp) / 1_000)
        )
    }
}

/// Reads Claude Desktop's local usage history strictly read-only.
///
/// The file is copied into memory under a plain `O_RDONLY` descriptor that is
/// closed before JSON parsing, so Claude Desktop can keep replacing it. Dejavu
/// never writes, locks, or deletes it, and never opens Desktop credentials,
/// cookies, or conversations. A parsed sample is cached by the file's
/// modification time and size so unchanged history is not reopened on every
/// refresh.
public actor ClaudeDesktopHistoryProvider {
    public static let maximumHistoryBytes = 16 * 1_024 * 1_024
    public static let historyFileName = "plan-usage-history.json"
    /// A Desktop install unused for a week no longer keeps a `--%` Claude slot.
    public static let maximumPlaceholderAge: TimeInterval = 7 * 24 * 60 * 60

    public nonisolated let historyURL: URL
    let freshnessPolicy: UsageFreshnessPolicy
    let maximumBytes: Int
    let now: @Sendable () -> Date

    private var cachedFingerprint: HistoryFingerprint?
    private var cachedSnapshot: ClaudeUsageSnapshot?

    public init(
        historyURL: URL,
        freshnessPolicy: UsageFreshnessPolicy = .claudeDesktopHistory,
        maximumBytes: Int = ClaudeDesktopHistoryProvider.maximumHistoryBytes,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.historyURL = historyURL
        self.freshnessPolicy = freshnessPolicy
        self.maximumBytes = max(1, maximumBytes)
        self.now = now
    }

    /// `~/Library/Application Support/Claude/plan-usage-history.json` for the
    /// given user Application Support directory.
    public static func defaultHistoryURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Claude", isDirectory: true)
            .appendingPathComponent(historyFileName, isDirectory: false)
    }

    public func fetchUsage(now: Date) async throws -> ClaudeUsageSnapshot {
        do {
            let fingerprint = try Self.fingerprint(of: historyURL, maximumBytes: maximumBytes)
            if fingerprint != cachedFingerprint {
                let history = try Self.readHistory(at: historyURL, maximumBytes: maximumBytes)
                let parsed: ClaudeUsageSnapshot
                do {
                    parsed = try ClaudeDesktopHistoryParser().parse(history.data)
                } catch {
                    throw ClaudeDesktopHistoryProviderError.invalidHistory
                }
                cachedFingerprint = history.fingerprint
                cachedSnapshot = parsed
            }
        } catch let error as ClaudeDesktopHistoryProviderError {
            // Desktop replaces the file while it writes. A sample read earlier
            // stays usable for its own freshness window, like on Windows.
            if let cached = freshCachedSnapshot(now: now) { return cached }
            throw error
        }

        if let fresh = freshCachedSnapshot(now: now) { return fresh }
        if let expired = expiredCachedPlaceholder(now: now) { return expired }
        throw ClaudeDesktopHistoryProviderError.historyStale
    }

    private func freshCachedSnapshot(now: Date) -> ClaudeUsageSnapshot? {
        guard let cachedSnapshot else { return nil }
        return freshnessPolicy.freshClaudeSnapshot(from: cachedSnapshot, now: now)
    }

    /// Desktop samples only intermittently while it runs and can skip longer
    /// than the freshness window. A parsed sample past that window keeps the
    /// Claude slot with every value `--%` and the sample time, never the
    /// expired percentages, until the sample is older than
    /// `maximumPlaceholderAge`.
    private func expiredCachedPlaceholder(now: Date) -> ClaudeUsageSnapshot? {
        guard let cachedSnapshot,
              cachedSnapshot.capturedAt <= now.addingTimeInterval(freshnessPolicy.maximumFutureClockSkew),
              now.timeIntervalSince(cachedSnapshot.capturedAt) <= Self.maximumPlaceholderAge else {
            return nil
        }
        return ClaudeUsageSnapshot(
            fiveHour: nil,
            weekly: nil,
            fable: nil,
            source: .desktopHistory,
            capturedAt: cachedSnapshot.capturedAt
        )
    }

    private static func fingerprint(of url: URL, maximumBytes: Int) throws -> HistoryFingerprint {
        var information = stat()
        let status = url.path.withCString { Darwin.lstat($0, &information) }
        guard status == 0 else {
            throw ClaudeDesktopHistoryProviderError.historyUnavailable
        }
        return try validatedFingerprint(information, maximumBytes: maximumBytes)
    }

    private static func validatedFingerprint(
        _ information: stat,
        maximumBytes: Int
    ) throws -> HistoryFingerprint {
        guard information.st_mode & S_IFMT == S_IFREG, information.st_size > 0 else {
            throw ClaudeDesktopHistoryProviderError.historyUnavailable
        }
        guard information.st_size <= off_t(maximumBytes) else {
            throw ClaudeDesktopHistoryProviderError.historyTooLarge
        }
        return HistoryFingerprint(
            modificationSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec),
            size: Int64(information.st_size)
        )
    }

    /// Copies the history into memory and closes Claude's file before the
    /// caller parses it.
    private static func readHistory(
        at url: URL,
        maximumBytes: Int
    ) throws -> (data: Data, fingerprint: HistoryFingerprint) {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw ClaudeDesktopHistoryProviderError.historyUnavailable
        }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0 else {
            throw ClaudeDesktopHistoryProviderError.historyUnavailable
        }
        let fingerprint = try validatedFingerprint(information, maximumBytes: maximumBytes)

        var result = Data()
        result.reserveCapacity(Int(fingerprint.size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw ClaudeDesktopHistoryProviderError.historyUnavailable
            }
            guard count > 0 else { return (result, fingerprint) }
            result.append(buffer, count: count)
            guard result.count <= maximumBytes else {
                throw ClaudeDesktopHistoryProviderError.historyTooLarge
            }
        }
    }
}

struct HistoryFingerprint: Hashable, Sendable {
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let size: Int64
}

private struct HistoryPayload: Decodable {
    let samples: [HistorySample]
}

private struct HistorySample: Decodable {
    let timestamp: Int64?
    let usage: HistoryUsage?

    enum CodingKeys: String, CodingKey {
        case timestamp = "t"
        case usage = "u"
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            timestamp = nil
            usage = nil
            return
        }
        timestamp = try? container.decodeIfPresent(Int64.self, forKey: .timestamp)
        usage = try? container.decodeIfPresent(HistoryUsage.self, forKey: .usage)
    }
}

private struct HistoryUsage: Decodable {
    let fiveHour: Double?
    let sevenDay: Double?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "fh"
        case sevenDay = "sd"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try? container.decodeIfPresent(Double.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(Double.self, forKey: .sevenDay)
    }
}
