import Foundation

public enum LocalDataResetError: Error, Sendable, Equatable {
    case unsafeDirectory
    case fileSystemFailure
}

/// Removes only Dejavu-owned support files. Provider credentials, Keychain
/// items, Claude settings, browser data, and conversation data are outside
/// this allow-list and can never be targeted by this type.
public struct LocalDataResetter: Sendable {
    public let directoryURL: URL

    private static let fixedFileNames: Set<String> = [
        "settings.json",
        "status.json",
        "claude-status.json",
        "claude-status-line-connection.json",
        "diagnostics.log",
        "diagnostics.previous.log"
    ]

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    @discardableResult
    public func reset() throws -> [String] {
        guard isSafeDirectory else { throw LocalDataResetError.unsafeDirectory }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }

        do {
            let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw LocalDataResetError.unsafeDirectory
            }

            let children = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            var removed: [String] = []
            for child in children where isAllowListedFileName(child.lastPathComponent) {
                try fileManager.removeItem(at: child)
                removed.append(child.lastPathComponent)
            }

            let binURL = directoryURL.appendingPathComponent("bin", isDirectory: true)
            if fileManager.fileExists(atPath: binURL.path) {
                let binAttributes = try fileManager.attributesOfItem(atPath: binURL.path)
                if binAttributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    try fileManager.removeItem(at: binURL)
                    removed.append("bin")
                } else {
                    let helperURL = binURL.appendingPathComponent(
                        "dejavu-claude-bridge",
                        isDirectory: false
                    )
                    if fileManager.fileExists(atPath: helperURL.path) {
                        try fileManager.removeItem(at: helperURL)
                        removed.append("bin/dejavu-claude-bridge")
                    }
                    if try fileManager.contentsOfDirectory(atPath: binURL.path).isEmpty {
                        try fileManager.removeItem(at: binURL)
                    }
                }
            }

            if try fileManager.contentsOfDirectory(atPath: directoryURL.path).isEmpty {
                try fileManager.removeItem(at: directoryURL)
            }
            return removed.sorted()
        } catch let error as LocalDataResetError {
            throw error
        } catch {
            throw LocalDataResetError.fileSystemFailure
        }
    }

    private var isSafeDirectory: Bool {
        guard directoryURL.isFileURL,
              directoryURL.path.hasPrefix("/"),
              directoryURL.path != "/",
              directoryURL.lastPathComponent.lowercased() == "dejavu" else {
            return false
        }
        return true
    }

    private func isAllowListedFileName(_ name: String) -> Bool {
        Self.fixedFileNames.contains(name)
            || (name.hasPrefix("settings.corrupt-") && name.hasSuffix(".json"))
    }
}
