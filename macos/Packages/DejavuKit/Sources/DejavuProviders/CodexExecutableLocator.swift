import Foundation

/// Finds a runnable Codex command without recursively searching the user's
/// home directory. The returned URL is canonicalized so callers don't retain a
/// package-manager shim symlink as process identity.
public struct CodexExecutableLocator: Sendable {
    private let environment: [String: String]
    private let homeDirectory: URL
    private let systemBinaryDirectories: [URL]
    private let applicationDirectories: [URL]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemBinaryDirectories: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
        ],
        applicationDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]
    ) {
        self.environment = environment
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.systemBinaryDirectories = systemBinaryDirectories
        self.applicationDirectories = applicationDirectories
    }

    /// Returns the first executable regular file in the documented search
    /// order. An invalid override is ignored rather than preventing fallback.
    public func locate() -> URL? {
        var seenPaths = Set<String>()

        for candidate in candidates() {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard seenPaths.insert(resolved.path).inserted else { continue }
            guard isRunnableFile(resolved) else { continue }
            return resolved
        }

        return nil
    }

    private func candidates() -> [URL] {
        var result: [URL] = []

        if let override = nonempty(environment["CODEX_CLI_PATH"]) {
            result.append(URL(fileURLWithPath: override))
        }

        result.append(homeDirectory.appendingPathComponent(".local/bin/codex"))
        result.append(contentsOf: systemBinaryDirectories.map {
            $0.appendingPathComponent("codex")
        })

        result.append(contentsOf: packageManagerCandidates())

        if let path = environment["PATH"] {
            result.append(contentsOf: path.split(separator: ":", omittingEmptySubsequences: true).map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("codex")
            })
        }

        for applications in applicationDirectories {
            result.append(
                applications.appendingPathComponent(
                    "ChatGPT.app/Contents/Resources/codex"
                )
            )
            result.append(
                applications.appendingPathComponent(
                    "Codex.app/Contents/Resources/codex"
                )
            )
        }

        return result
    }

    private func packageManagerCandidates() -> [URL] {
        var result = [
            homeDirectory.appendingPathComponent(".npm/bin/codex"),
            homeDirectory.appendingPathComponent(".npm-global/bin/codex"),
            homeDirectory.appendingPathComponent("Library/pnpm/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex"),
            homeDirectory.appendingPathComponent(".asdf/shims/codex"),
            homeDirectory.appendingPathComponent(".local/share/fnm/aliases/default/bin/codex")
        ]

        result.append(contentsOf: versionedCandidates(
            below: homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true),
            suffix: "bin/codex"
        ))
        result.append(contentsOf: versionedCandidates(
            below: homeDirectory.appendingPathComponent(
                ".local/share/fnm/node-versions",
                isDirectory: true
            ),
            suffix: "installation/bin/codex"
        ))

        return result
    }

    /// Enumerating one known versions directory is bounded and avoids the
    /// privacy and latency cost of a recursive home-directory search.
    private func versionedCandidates(below directory: URL, suffix: String) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children
            .filter { (try? $0.resourceValues(forKeys: keys).isDirectory) == true }
            .sorted { compareVersionNames($0.lastPathComponent, $1.lastPathComponent) }
            .prefix(32)
            .map { $0.appendingPathComponent(suffix) }
    }

    private func compareVersionNames(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedDescending
    }

    private func isRunnableFile(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard (try? url.resourceValues(forKeys: keys).isRegularFile) == true else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
