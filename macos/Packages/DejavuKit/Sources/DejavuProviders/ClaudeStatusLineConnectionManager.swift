import Darwin
import Foundation

/// All paths are injected deliberately. Constructing this value, or a
/// ``ClaudeStatusLineConnectionManager``, performs no file-system access.
public struct ClaudeStatusLineConnectionConfiguration: Sendable, Equatable {
    public static let metadataFileName = "claude-status-line-connection.json"

    public let settingsURL: URL
    public let applicationSupportDirectoryURL: URL
    public let bridgeExecutableURL: URL
    public let snapshotURL: URL

    public var metadataURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent(Self.metadataFileName)
    }

    public var installedBridgeURL: URL {
        applicationSupportDirectoryURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("dejavu-claude-bridge")
    }

    public init(
        settingsURL: URL,
        applicationSupportDirectoryURL: URL,
        bridgeExecutableURL: URL,
        snapshotURL: URL? = nil
    ) {
        self.settingsURL = settingsURL.standardizedFileURL
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL.standardizedFileURL
        self.bridgeExecutableURL = bridgeExecutableURL.standardizedFileURL
        self.snapshotURL = (snapshotURL ?? applicationSupportDirectoryURL.appendingPathComponent(
            "claude-status.json"
        )).standardizedFileURL
    }
}

public enum ClaudeStatusLineConnectResult: Sendable, Equatable {
    case connected
    case alreadyConnected
}

public enum ClaudeStatusLineDisconnectResult: Sendable, Equatable {
    case disconnected
    case notConnected
}

/// Errors intentionally contain neither paths nor underlying error text. A
/// settings file or an existing command can contain credentials.
public enum ClaudeStatusLineConnectionError: Error, Sendable, Equatable {
    case invalidConfiguration
    case bridgeUnavailable
    case settingsUnsafe
    case settingsTooLarge
    case settingsMalformed
    case metadataStorageUnsafe
    case snapshotStorageUnsafe
    case metadataTooLarge
    case metadataMalformed
    case unsupportedExistingCommand
    case conflict
    case fileSystemFailure
}

/// Installs the bundled bridge only in response to an explicit `connect()`
/// call. There is intentionally no convenience initializer that discovers or
/// reads `~/.claude`.
public actor ClaudeStatusLineConnectionManager {
    static let maximumSettingsBytes = 2 * 1_024 * 1_024
    static let maximumMetadataBytes = 8 * 1_024 * 1_024
    static let maximumChainedCommandBytes = 64 * 1_024

    private static let statusLineKey = "statusLine"
    private static let snapshotEnvironmentKey = "DEJAVU_CLAUDE_SNAPSHOT_PATH"
    private static let chainEnvironmentKey = "DEJAVU_CLAUDE_CHAIN_COMMAND"

    private let configuration: ClaudeStatusLineConnectionConfiguration

    public init(configuration: ClaudeStatusLineConnectionConfiguration) {
        self.configuration = configuration
    }

    @discardableResult
    public func connect() throws -> ClaudeStatusLineConnectResult {
        try validateConfiguration()

        if let metadata = try loadMetadataIfPresent() {
            var settings = try loadSettings()
            if currentStatusLine(in: settings.root, matches: metadata.managedStatusLine) {
                try validateBridgeExecutable()
                try validateSnapshotStorage()
                try installBridge()
                return .alreadyConnected
            }

            guard currentStatusLineMatchesOriginal(in: settings.root, metadata: metadata) else {
                throw ClaudeStatusLineConnectionError.conflict
            }
            try validateBridgeExecutable()
            try validateSnapshotStorage()
            try installBridge()
            settings.root[Self.statusLineKey] = try decodeManagedStatusLine(
                metadata.managedStatusLine
            )
            try writeSettings(try encodeRoot(settings.root))
            return .connected
        }

        try validateBridgeExecutable()
        try validateSnapshotStorage()
        let settings = try loadSettings()
        var updatedRoot = settings.root
        let hadOriginalStatusLine = updatedRoot.keys.contains(Self.statusLineKey)
        let originalStatusLine = updatedRoot[Self.statusLineKey]
        let managedStatusLine = try makeManagedStatusLine(from: originalStatusLine)
        updatedRoot[Self.statusLineKey] = managedStatusLine

        let originalData = try originalStatusLine.map(canonicalFragment)
        let managedData = try canonicalFragment(managedStatusLine)
        let metadata = ConnectionMetadata(
            schemaVersion: ConnectionMetadata.currentSchemaVersion,
            settingsFileExisted: settings.fileExisted,
            hadOriginalStatusLine: hadOriginalStatusLine,
            originalStatusLine: originalData,
            managedStatusLine: managedData
        )
        let metadataData = try encodeMetadata(metadata)
        let settingsData = try encodeRoot(updatedRoot)

        try installBridge()
        try writeMetadata(metadataData)
        do {
            try writeSettings(settingsData)
        } catch {
            removeMetadataIfUnchanged(metadataData)
            throw error
        }

        return .connected
    }

    @discardableResult
    public func disconnect() throws -> ClaudeStatusLineDisconnectResult {
        try validateConfiguration()
        guard let metadata = try loadMetadataIfPresent() else {
            return .notConnected
        }

        let settings = try loadSettings()
        guard currentStatusLine(in: settings.root, matches: metadata.managedStatusLine) else {
            throw ClaudeStatusLineConnectionError.conflict
        }

        var restoredRoot = settings.root
        if metadata.hadOriginalStatusLine {
            guard let originalData = metadata.originalStatusLine else {
                throw ClaudeStatusLineConnectionError.metadataMalformed
            }
            restoredRoot[Self.statusLineKey] = try decodeFragment(originalData)
        } else {
            restoredRoot.removeValue(forKey: Self.statusLineKey)
        }

        if !metadata.settingsFileExisted, restoredRoot.isEmpty {
            try removeSettingsFile()
        } else {
            try writeSettings(try encodeRoot(restoredRoot))
        }
        try removeMetadataFile()
        return .disconnected
    }

    private func validateConfiguration() throws {
        let urls = [
            configuration.settingsURL,
            configuration.applicationSupportDirectoryURL,
            configuration.bridgeExecutableURL,
            configuration.snapshotURL,
            configuration.metadataURL,
            configuration.installedBridgeURL
        ]
        guard urls.allSatisfy({
            $0.isFileURL && $0.path.hasPrefix("/") && !$0.path.contains("\0")
        }) else {
            throw ClaudeStatusLineConnectionError.invalidConfiguration
        }

        let settingsParent = configuration.settingsURL.deletingLastPathComponent()
        guard configuration.settingsURL.path != "/",
              configuration.applicationSupportDirectoryURL.path != "/",
              settingsParent.path != "/",
              configuration.settingsURL != configuration.metadataURL,
              configuration.settingsURL != configuration.bridgeExecutableURL,
              configuration.settingsURL != configuration.snapshotURL,
              configuration.settingsURL != configuration.installedBridgeURL,
              configuration.metadataURL != configuration.bridgeExecutableURL,
              configuration.metadataURL != configuration.snapshotURL,
              configuration.metadataURL != configuration.installedBridgeURL,
              configuration.bridgeExecutableURL != configuration.snapshotURL,
              configuration.bridgeExecutableURL != configuration.installedBridgeURL,
              configuration.snapshotURL != configuration.installedBridgeURL else {
            throw ClaudeStatusLineConnectionError.invalidConfiguration
        }
    }

    private func validateBridgeExecutable() throws {
        let node: FileNode
        do {
            node = try fileNode(at: configuration.bridgeExecutableURL)
        } catch {
            throw ClaudeStatusLineConnectionError.bridgeUnavailable
        }
        guard case .regular = node,
              Darwin.access(configuration.bridgeExecutableURL.path, X_OK) == 0 else {
            throw ClaudeStatusLineConnectionError.bridgeUnavailable
        }
    }

    private func installBridge() throws {
        let sourceData: Data
        do {
            sourceData = try readBoundedRegularFile(
                at: configuration.bridgeExecutableURL,
                maximumBytes: 16 * 1_024 * 1_024
            )
        } catch {
            throw ClaudeStatusLineConnectionError.bridgeUnavailable
        }

        do {
            try atomicWrite(
                sourceData,
                to: configuration.installedBridgeURL,
                filePermissions: 0o700
            )
        } catch FileOperationError.unsafe {
            throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func validateSnapshotStorage() throws {
        do {
            switch try fileNode(at: configuration.snapshotURL.deletingLastPathComponent()) {
            case .missing, .directory:
                break
            case .regular, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.snapshotStorageUnsafe
            }
            switch try fileNode(at: configuration.snapshotURL) {
            case .missing, .regular:
                break
            case .directory, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.snapshotStorageUnsafe
            }
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func loadSettings() throws -> LoadedSettings {
        let data: Data
        do {
            switch try fileNode(at: configuration.settingsURL.deletingLastPathComponent()) {
            case .missing, .directory:
                break
            case .regular, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.settingsUnsafe
            }
            switch try fileNode(at: configuration.settingsURL) {
            case .missing:
                return LoadedSettings(root: [:], fileExisted: false)
            case .regular:
                data = try readBoundedRegularFile(
                    at: configuration.settingsURL,
                    maximumBytes: Self.maximumSettingsBytes
                )
            case .directory, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.settingsUnsafe
            }
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch SecureReadError.tooLarge {
            throw ClaudeStatusLineConnectionError.settingsTooLarge
        } catch SecureReadError.unsafe {
            throw ClaudeStatusLineConnectionError.settingsUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }

        guard data.count <= Self.maximumSettingsBytes else {
            throw ClaudeStatusLineConnectionError.settingsTooLarge
        }
        do {
            let value = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = value as? [String: Any] else {
                throw ClaudeStatusLineConnectionError.settingsMalformed
            }
            return LoadedSettings(root: root, fileExisted: true)
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch {
            throw ClaudeStatusLineConnectionError.settingsMalformed
        }
    }

    private func loadMetadataIfPresent() throws -> ConnectionMetadata? {
        let data: Data
        do {
            switch try fileNode(at: configuration.applicationSupportDirectoryURL) {
            case .missing, .directory:
                break
            case .regular, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
            }
            switch try fileNode(at: configuration.metadataURL) {
            case .missing:
                return nil
            case .regular:
                data = try readBoundedRegularFile(
                    at: configuration.metadataURL,
                    maximumBytes: Self.maximumMetadataBytes
                )
            case .directory, .symbolicLink, .other:
                throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
            }
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch SecureReadError.tooLarge {
            throw ClaudeStatusLineConnectionError.metadataTooLarge
        } catch SecureReadError.unsafe {
            throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }

        guard data.count <= Self.maximumMetadataBytes else {
            throw ClaudeStatusLineConnectionError.metadataTooLarge
        }
        do {
            let metadata = try JSONDecoder().decode(ConnectionMetadata.self, from: data)
            guard metadata.schemaVersion == ConnectionMetadata.currentSchemaVersion,
                  metadata.hadOriginalStatusLine == (metadata.originalStatusLine != nil) else {
                throw ClaudeStatusLineConnectionError.metadataMalformed
            }

            _ = try decodeManagedStatusLine(metadata.managedStatusLine)
            if let original = metadata.originalStatusLine {
                _ = try canonicalFragment(from: original)
            }
            return metadata
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch {
            throw ClaudeStatusLineConnectionError.metadataMalformed
        }
    }

    private func makeManagedStatusLine(from original: Any?) throws -> [String: Any] {
        var managed = original as? [String: Any] ?? [:]
        var environment = [
            "\(Self.snapshotEnvironmentKey)=\(configuration.snapshotURL.path)"
        ]

        if let object = original as? [String: Any],
           object["type"] as? String == "command" {
            guard let command = object["command"] as? String,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  command.utf8.count <= Self.maximumChainedCommandBytes,
                  !command.contains("\0") else {
                throw ClaudeStatusLineConnectionError.unsupportedExistingCommand
            }
            environment.append("\(Self.chainEnvironmentKey)=\(command)")
        }

        let environmentArguments = environment.map(shellQuote).joined(separator: " ")
        let bridgeArgument = shellQuote(configuration.installedBridgeURL.path)
        managed["type"] = "command"
        managed["command"] = "exec /usr/bin/env \(environmentArguments) \(bridgeArgument)"
        return managed
    }

    private func currentStatusLine(
        in root: [String: Any],
        matches expectedData: Data
    ) -> Bool {
        guard root.keys.contains(Self.statusLineKey),
              let current = root[Self.statusLineKey],
              let currentData = try? canonicalFragment(current),
              let expectedCanonical = try? canonicalFragment(from: expectedData) else {
            return false
        }
        return currentData == expectedCanonical
    }

    private func currentStatusLineMatchesOriginal(
        in root: [String: Any],
        metadata: ConnectionMetadata
    ) -> Bool {
        guard metadata.hadOriginalStatusLine else {
            return !root.keys.contains(Self.statusLineKey)
        }
        guard let original = metadata.originalStatusLine else { return false }
        return currentStatusLine(in: root, matches: original)
    }

    private func decodeManagedStatusLine(_ data: Data) throws -> [String: Any] {
        let value = try decodeFragment(data)
        guard let object = value as? [String: Any],
              object["type"] as? String == "command",
              let command = object["command"] as? String,
              !command.isEmpty else {
            throw ClaudeStatusLineConnectionError.metadataMalformed
        }
        return object
    }

    private func canonicalFragment(_ value: Any) throws -> Data {
        guard JSONSerialization.isValidJSONObject([value]) else {
            throw ClaudeStatusLineConnectionError.settingsMalformed
        }
        do {
            return try JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw ClaudeStatusLineConnectionError.settingsMalformed
        }
    }

    private func canonicalFragment(from data: Data) throws -> Data {
        do {
            let value = try decodeFragment(data)
            return try JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch {
            throw ClaudeStatusLineConnectionError.metadataMalformed
        }
    }

    private func decodeFragment(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw ClaudeStatusLineConnectionError.metadataMalformed
        }
    }

    private func encodeRoot(_ root: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(root) else {
            throw ClaudeStatusLineConnectionError.settingsMalformed
        }
        do {
            var data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            data.append(0x0A)
            return data
        } catch {
            throw ClaudeStatusLineConnectionError.settingsMalformed
        }
    }

    private func encodeMetadata(_ metadata: ConnectionMetadata) throws -> Data {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(metadata)
            data.append(0x0A)
            guard data.count <= Self.maximumMetadataBytes else {
                throw ClaudeStatusLineConnectionError.metadataTooLarge
            }
            return data
        } catch let error as ClaudeStatusLineConnectionError {
            throw error
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func writeSettings(_ data: Data) throws {
        do {
            try atomicWrite(
                data,
                to: configuration.settingsURL,
                filePermissions: nil
            )
        } catch FileOperationError.unsafe {
            throw ClaudeStatusLineConnectionError.settingsUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func writeMetadata(_ data: Data) throws {
        do {
            try atomicWrite(
                data,
                to: configuration.metadataURL,
                filePermissions: 0o600
            )
        } catch FileOperationError.unsafe {
            throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func removeSettingsFile() throws {
        do {
            try removeRegularFileIfPresent(at: configuration.settingsURL)
        } catch FileOperationError.unsafe {
            throw ClaudeStatusLineConnectionError.settingsUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func removeMetadataFile() throws {
        do {
            try removeRegularFileIfPresent(at: configuration.metadataURL)
        } catch FileOperationError.unsafe {
            throw ClaudeStatusLineConnectionError.metadataStorageUnsafe
        } catch {
            throw ClaudeStatusLineConnectionError.fileSystemFailure
        }
    }

    private func removeMetadataIfUnchanged(_ expectedData: Data) {
        guard let current = try? readBoundedRegularFile(
            at: configuration.metadataURL,
            maximumBytes: Self.maximumMetadataBytes
        ), current == expectedData else {
            return
        }
        try? removeRegularFileIfPresent(at: configuration.metadataURL)
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct LoadedSettings {
    var root: [String: Any]
    let fileExisted: Bool
}

private struct ConnectionMetadata: Codable, Sendable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let settingsFileExisted: Bool
    let hadOriginalStatusLine: Bool
    let originalStatusLine: Data?
    let managedStatusLine: Data
}

private enum FileNode {
    case missing
    case regular
    case directory
    case symbolicLink
    case other
}

private enum SecureReadError: Error {
    case unsafe
    case tooLarge
    case failed
}

private enum FileOperationError: Error {
    case unsafe
    case failed
}

private func fileNode(at url: URL) throws -> FileNode {
    var information = stat()
    let result = url.path.withCString { Darwin.lstat($0, &information) }
    if result != 0 {
        if errno == ENOENT { return .missing }
        throw FileOperationError.failed
    }

    switch information.st_mode & S_IFMT {
    case S_IFREG: return .regular
    case S_IFDIR: return .directory
    case S_IFLNK: return .symbolicLink
    default: return .other
    }
}

private func readBoundedRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
    let descriptor = url.path.withCString {
        Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    }
    guard descriptor >= 0 else {
        if errno == ELOOP { throw SecureReadError.unsafe }
        throw SecureReadError.failed
    }
    defer { Darwin.close(descriptor) }

    var information = stat()
    guard Darwin.fstat(descriptor, &information) == 0 else {
        throw SecureReadError.failed
    }
    guard information.st_mode & S_IFMT == S_IFREG else {
        throw SecureReadError.unsafe
    }
    guard information.st_size >= 0,
          information.st_size <= off_t(maximumBytes) else {
        throw SecureReadError.tooLarge
    }

    var result = Data()
    let chunkSize = 64 * 1_024
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    while true {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count >= 0 else {
            if errno == EINTR { continue }
            throw SecureReadError.failed
        }
        guard count > 0 else { return result }
        result.append(buffer, count: count)
        if result.count > maximumBytes {
            throw SecureReadError.tooLarge
        }
    }
}

private func ensurePrivateDirectory(_ directory: URL) throws {
    switch try fileNode(at: directory) {
    case .missing:
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw FileOperationError.failed
        }
    case .directory:
        break
    case .regular, .symbolicLink, .other:
        throw FileOperationError.unsafe
    }
}

private func atomicWrite(
    _ data: Data,
    to destination: URL,
    filePermissions requestedPermissions: mode_t?
) throws {
    let parent = destination.deletingLastPathComponent()
    try ensurePrivateDirectory(parent)

    let existingPermissions: mode_t?
    switch try fileNode(at: destination) {
    case .missing:
        existingPermissions = nil
    case .regular:
        var information = stat()
        guard destination.path.withCString({ Darwin.lstat($0, &information) }) == 0 else {
            throw FileOperationError.failed
        }
        existingPermissions = information.st_mode & 0o7777
    case .directory, .symbolicLink, .other:
        throw FileOperationError.unsafe
    }

    let finalPermissions = requestedPermissions ?? existingPermissions ?? 0o600

    let temporaryURL = parent.appendingPathComponent(
        ".\(destination.lastPathComponent).\(UUID().uuidString).tmp"
    )
    let descriptor = temporaryURL.path.withCString {
        Darwin.open(
            $0,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            finalPermissions
        )
    }
    guard descriptor >= 0 else { throw FileOperationError.failed }

    var shouldRemoveTemporaryFile = true
    defer {
        Darwin.close(descriptor)
        if shouldRemoveTemporaryFile {
            _ = temporaryURL.path.withCString { Darwin.unlink($0) }
        }
    }

    do {
        try data.withUnsafeBytes { rawBuffer in
            guard var baseAddress = rawBuffer.baseAddress else { return }
            var bytesRemaining = rawBuffer.count
            while bytesRemaining > 0 {
                let written = Darwin.write(descriptor, baseAddress, bytesRemaining)
                guard written >= 0 else {
                    if errno == EINTR { continue }
                    throw FileOperationError.failed
                }
                guard written > 0 else { throw FileOperationError.failed }
                bytesRemaining -= written
                baseAddress = baseAddress.advanced(by: written)
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw FileOperationError.failed }
        guard temporaryURL.path.withCString({ temporaryPath in
            destination.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }) == 0 else {
            throw FileOperationError.failed
        }
        shouldRemoveTemporaryFile = false
        guard Darwin.chmod(destination.path, finalPermissions) == 0 else {
            throw FileOperationError.failed
        }

        let directoryDescriptor = parent.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC)
        }
        if directoryDescriptor >= 0 {
            _ = Darwin.fsync(directoryDescriptor)
            Darwin.close(directoryDescriptor)
        }
    } catch {
        throw error
    }
}

private func removeRegularFileIfPresent(at url: URL) throws {
    switch try fileNode(at: url) {
    case .missing:
        return
    case .regular:
        break
    case .directory, .symbolicLink, .other:
        throw FileOperationError.unsafe
    }

    guard url.path.withCString({ Darwin.unlink($0) }) == 0 else {
        throw FileOperationError.failed
    }
}
