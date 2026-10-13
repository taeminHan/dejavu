import Foundation
import DejavuDomain

/// Resolves paths without opening Claude settings or credential files.
public struct ClaudeConfigurationPaths: Sendable, Equatable {
    public let directoryURL: URL
    public var settingsURL: URL { directoryURL.appendingPathComponent("settings.json") }

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        selectedDirectory: URL? = nil
    ) {
        if let selectedDirectory, selectedDirectory.isFileURL, selectedDirectory.path != "/" {
            directoryURL = selectedDirectory.standardizedFileURL
        } else if let configured = environment["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  configured.hasPrefix("/"), configured != "/", !configured.contains("\0") {
            directoryURL = URL(fileURLWithPath: configured, isDirectory: true).standardizedFileURL
        } else {
            directoryURL = homeDirectory.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
        }
    }
}

public enum ClaudeLoginCommandError: Error, Sendable, Equatable {
    case executableUnavailable
    case unsupportedCredentialIdentity
}

enum ClaudeCredentialAccount {
    /// Official CLI 2.1.291 iT(): USER || os.userInfo().username, restricted
    /// to ASCII account identifiers; invalid values use its fixed fallback.
    static func resolve(environment: [String: String], userName: String) -> String {
        let account = environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? userName
        let isAllowed = !account.isEmpty && account.utf8.allSatisfy {
            switch $0 {
            case 45, 46, 48...57, 65...90, 95, 97...122: true
            default: false
            }
        }
        return isAllowed ? account : "claude-code-user"
    }
}

/// Produces an explicit official `auth login` command for Terminal. Every
/// external path is POSIX-quoted; no shell interpolation or clipboard access.
public struct ClaudeLoginCommandBuilder: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let binaryDirectories: [URL]
    private let applicationDirectories: [URL]
    private let credentialAccount: String

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        binaryDirectories: [URL] = [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")],
        applicationDirectories: [URL] = [URL(fileURLWithPath: "/Applications")]
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.binaryDirectories = binaryDirectories
        self.applicationDirectories = applicationDirectories
        credentialAccount = ClaudeCredentialAccount.resolve(environment: environment, userName: NSUserName())
    }

    public func executableURL() -> URL? {
        var candidates: [URL] = []
        if let path = environment["CLAUDE_CODE_PATH"], path.hasPrefix("/") {
            candidates.append(URL(fileURLWithPath: path))
        }
        candidates += [".local/bin/claude", ".claude/local/claude", ".npm/bin/claude", ".npm-global/bin/claude", "Library/pnpm/claude", ".volta/bin/claude", ".asdf/shims/claude", ".local/share/fnm/aliases/default/bin/claude"].map { homeDirectory.appendingPathComponent($0) }
        candidates += binaryDirectories.map { $0.appendingPathComponent("claude") }
        for (folder, suffix) in [(".nvm/versions/node", "bin/claude"), (".local/share/fnm/node-versions", "installation/bin/claude")] {
            let versions = (try? FileManager.default.contentsOfDirectory(at: homeDirectory.appendingPathComponent(folder), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            candidates += versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.prefix(32).map { $0.appendingPathComponent(suffix) }
        }
        candidates += (environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: String($0)).appendingPathComponent("claude")
        }
        candidates += (applicationDirectories + [homeDirectory.appendingPathComponent("Applications")]).map {
            $0.appendingPathComponent("Claude.app/Contents/Resources/claude")
        }
        return candidates.map { $0.standardizedFileURL.resolvingSymlinksInPath() }.first {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    public func command(
        configurationPaths: ClaudeConfigurationPaths = ClaudeConfigurationPaths(),
        credentialIdentity: ClaudeCredentialIdentity = .standard
    ) throws -> String {
        let defaultDirectory = homeDirectory.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
        guard credentialIdentity != .previousDejavuDefault || configurationPaths.directoryURL == defaultDirectory else {
            throw ClaudeLoginCommandError.unsupportedCredentialIdentity
        }
        guard let executable = executableURL() else { throw ClaudeLoginCommandError.executableUnavailable }
        // The official CLI keys credentials by whether CLAUDE_CONFIG_DIR is
        // present, not just by its resolved path. Explicitly setting even the
        // default directory therefore creates a different Keychain identity.
        // Clear both overrides inherited from Terminal before selecting the
        // intended profile. A custom profile remains an explicit choice.
        let environmentCommand: String
        if configurationPaths.directoryURL == defaultDirectory, credentialIdentity == .standard {
            environmentCommand = "/usr/bin/env -u CLAUDE_CONFIG_DIR -u CLAUDE_SECURESTORAGE_CONFIG_DIR "
        } else {
            environmentCommand = "/usr/bin/env -u CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR="
                + Self.shellQuote(configurationPaths.directoryURL.path) + " "
        }
        return environmentCommand + "USER=" + Self.shellQuote(credentialAccount) + " "
            + Self.shellQuote(executable.path) + " auth login"
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
