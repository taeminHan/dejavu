import Darwin
import Foundation

private enum BridgeConfiguration {
    static let schemaVersion = 1
    static let maximumInputBytes = 2 * 1_024 * 1_024
    static let readChunkBytes = 64 * 1_024
    static let snapshotPathEnvironmentKey = "DEJAVU_CLAUDE_SNAPSHOT_PATH"
    static let chainCommandEnvironmentKey = "DEJAVU_CLAUDE_CHAIN_COMMAND"
    static let chainDepthEnvironmentKey = "DEJAVU_CLAUDE_CHAIN_DEPTH"
}

private enum BridgeError: Error {
    case inputTooLarge
    case invalidSnapshotPath
    case cannotCreateLock
    case cannotLock
    case symbolicLinkDestination
    case cannotCreateTemporaryFile
    case chainRecursion
}

// Deliberately declares only rate_limits. JSONDecoder ignores every other Claude
// status-line field without materializing it in the bridge's data model.
private struct ClaudeStatusInput: Decodable {
    let rateLimits: InputRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct InputRateLimits: Decodable {
    let fiveHour: InputRateLimitWindow?
    let sevenDay: InputRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = Self.decodeWindow(.fiveHour, from: container)
        sevenDay = Self.decodeWindow(.sevenDay, from: container)
    }

    private static func decodeWindow(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> InputRateLimitWindow? {
        do {
            return try container.decodeIfPresent(InputRateLimitWindow.self, forKey: key)
        } catch {
            return nil
        }
    }
}

private struct InputRateLimitWindow: Decodable {
    let usedPercentage: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decoded = try? container.decode(Double.self, forKey: .usedPercentage),
           decoded.isFinite {
            usedPercentage = decoded
        } else {
            usedPercentage = nil
        }

        let instant: FlexibleInstant?
        do {
            instant = try container.decodeIfPresent(FlexibleInstant.self, forKey: .resetsAt)
        } catch {
            instant = nil
        }
        resetsAt = instant?.normalizedISO8601
    }
}

private struct FlexibleInstant: Decodable {
    let normalizedISO8601: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            normalizedISO8601 = ISO8601.normalize(string)
            return
        }

        if let integer = try? container.decode(Int64.self) {
            normalizedISO8601 = ISO8601.fromEpochSeconds(Double(integer))
            return
        }

        if let number = try? container.decode(Double.self) {
            normalizedISO8601 = ISO8601.fromEpochSeconds(number)
            return
        }

        normalizedISO8601 = nil
    }
}

private struct BridgeSnapshot: Encodable {
    let schemaVersion: Int
    let capturedAt: String
    let rateLimits: SnapshotRateLimits?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case capturedAt = "captured_at"
        case rateLimits = "rate_limits"
    }
}

private struct SnapshotRateLimits: Encodable {
    let fiveHour: SnapshotRateLimitWindow?
    let sevenDay: SnapshotRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    init?(_ input: InputRateLimits) {
        fiveHour = input.fiveHour.flatMap(SnapshotRateLimitWindow.init)
        sevenDay = input.sevenDay.flatMap(SnapshotRateLimitWindow.init)
        if fiveHour == nil, sevenDay == nil {
            return nil
        }
    }
}

private struct SnapshotRateLimitWindow: Encodable {
    let usedPercentage: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init?(_ input: InputRateLimitWindow) {
        guard let usedPercentage = input.usedPercentage else { return nil }
        self.usedPercentage = usedPercentage
        resetsAt = input.resetsAt
    }
}

private struct ExistingSnapshotHeader: Decodable {
    let capturedAt: String

    enum CodingKeys: String, CodingKey {
        case capturedAt = "captured_at"
    }
}

private enum ISO8601 {
    static func now(_ date: Date) -> String {
        format(date)
    }

    static func normalize(_ value: String) -> String? {
        guard let date = parse(value) else { return nil }
        return format(date)
    }

    static func fromEpochSeconds(_ value: Double) -> String? {
        guard value.isFinite, value >= 0, value <= 32_503_680_000 else { return nil }
        return format(Date(timeIntervalSince1970: value))
    }

    static func parse(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct AtomicSnapshotWriter {
    let fileManager = FileManager.default

    func write(_ data: Data, capturedAt: Date, to destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try createPrivateDirectoryIfNeeded(parent)
        try rejectSymbolicLink(at: destination)

        let lockURL = parent.appendingPathComponent(".\(destination.lastPathComponent).lock")
        let lockDescriptor = lockURL.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR | O_NOFOLLOW | O_EXLOCK, S_IRUSR | S_IWUSR)
        }
        guard lockDescriptor >= 0 else { throw BridgeError.cannotCreateLock }
        defer { Darwin.close(lockDescriptor) }

        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lockURL.path)
        try rejectSymbolicLink(at: destination)

        if existingSnapshot(at: destination, isNewerThan: capturedAt) {
            return
        }

        let temporaryURL = parent.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw BridgeError.cannotCreateTemporaryFile
        }

        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(
                destination,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destination)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    private func createPrivateDirectoryIfNeeded(_ directory: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw BridgeError.invalidSnapshotPath }
            return
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func rejectSymbolicLink(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw BridgeError.symbolicLinkDestination
        }
    }

    private func existingSnapshot(at url: URL, isNewerThan candidate: Date) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let header = try? JSONDecoder().decode(ExistingSnapshotHeader.self, from: data),
              let existingDate = ISO8601.parse(header.capturedAt) else {
            return false
        }
        return existingDate > candidate
    }
}

private struct BridgeRunner {
    private let environment: [String: String]
    private let startedAt: Date

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        startedAt: Date = Date()
    ) {
        self.environment = environment
        self.startedAt = startedAt
    }

    func run() -> Int32 {
        let input: Data
        do {
            input = try readBoundedStandardInput()
        } catch {
            writeDiagnostic("input rejected")
            return 65
        }

        var captureSucceeded = false
        do {
            let decoded = try JSONDecoder().decode(ClaudeStatusInput.self, from: input)
            let snapshot = BridgeSnapshot(
                schemaVersion: BridgeConfiguration.schemaVersion,
                capturedAt: ISO8601.now(startedAt),
                rateLimits: decoded.rateLimits.flatMap(SnapshotRateLimits.init)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var encoded = try encoder.encode(snapshot)
            encoded.append(0x0A)
            try AtomicSnapshotWriter().write(
                encoded,
                capturedAt: startedAt,
                to: try snapshotURL()
            )
            captureSucceeded = true
        } catch {
            // Never include input, paths, commands or decoder details in stderr.
            writeDiagnostic("snapshot capture failed")
        }

        if let command = configuredChainCommand() {
            do {
                return try runChainedCommand(command, input: input)
            } catch {
                writeDiagnostic("chained command failed")
                return 70
            }
        }

        return captureSucceeded ? 0 : 65
    }

    private func readBoundedStandardInput() throws -> Data {
        var result = Data()

        while true {
            let remaining = BridgeConfiguration.maximumInputBytes - result.count
            let nextReadSize = min(BridgeConfiguration.readChunkBytes, remaining + 1)
            guard let chunk = try FileHandle.standardInput.read(upToCount: nextReadSize),
                  !chunk.isEmpty else {
                return result
            }
            result.append(chunk)
            if result.count > BridgeConfiguration.maximumInputBytes {
                throw BridgeError.inputTooLarge
            }
        }
    }

    private func snapshotURL() throws -> URL {
        if let configuredPath = environment[BridgeConfiguration.snapshotPathEnvironmentKey],
           !configuredPath.isEmpty {
            guard configuredPath.hasPrefix("/") else { throw BridgeError.invalidSnapshotPath }
            let url = URL(fileURLWithPath: configuredPath).standardizedFileURL
            return url
        }

        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BridgeError.invalidSnapshotPath
        }
        return applicationSupport
            .appendingPathComponent("dejavu", isDirectory: true)
            .appendingPathComponent("claude-status.json", isDirectory: false)
    }

    private func configuredChainCommand() -> String? {
        guard let raw = environment[BridgeConfiguration.chainCommandEnvironmentKey] else {
            return nil
        }
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return command.isEmpty ? nil : command
    }

    private func runChainedCommand(_ command: String, input: Data) throws -> Int32 {
        guard environment[BridgeConfiguration.chainDepthEnvironmentKey] == nil else {
            throw BridgeError.chainRecursion
        }

        let process = Process()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]

        var childEnvironment = environment
        childEnvironment.removeValue(forKey: BridgeConfiguration.chainCommandEnvironmentKey)
        childEnvironment[BridgeConfiguration.chainDepthEnvironmentKey] = "1"
        process.environment = childEnvironment
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        do {
            try inputPipe.fileHandleForWriting.write(contentsOf: input)
            try inputPipe.fileHandleForWriting.close()
        } catch {
            try? inputPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func writeDiagnostic(_ category: String) {
        let line = "dejavu-claude-bridge: \(category)\n"
        if let data = line.data(using: .utf8) {
            try? FileHandle.standardError.write(contentsOf: data)
        }
    }
}

Darwin.exit(BridgeRunner().run())
