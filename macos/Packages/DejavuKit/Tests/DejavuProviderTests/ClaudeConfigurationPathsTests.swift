import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class ClaudeConfigurationPathsTests: XCTestCase {
    func testResolvesExplicitAndEnvironmentProfilesWithoutReadingThem() {
        let home = URL(fileURLWithPath: "/synthetic/user")
        XCTAssertEqual(ClaudeConfigurationPaths(environment: [:], homeDirectory: home).settingsURL.path, "/synthetic/user/.claude/settings.json")
        XCTAssertEqual(ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/synthetic/work profile"], homeDirectory: home).settingsURL.path, "/synthetic/work profile/settings.json")
        XCTAssertEqual(ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/synthetic/ignored"], homeDirectory: home, selectedDirectory: URL(fileURLWithPath: "/synthetic/selected")).directoryURL.path, "/synthetic/selected")
        XCTAssertEqual(ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/"], homeDirectory: home).directoryURL.path, "/synthetic/user/.claude")
    }

    func testLoginCommandFindsExecutableAndQuotesShellMetacharacters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-claude-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude ' quoted $(never-run)")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let profile = directory.appendingPathComponent("profile ' $(never-run)")
        let builder = ClaudeLoginCommandBuilder(environment: ["CLAUDE_CODE_PATH": executable.path, "USER": "synthetic-user"], homeDirectory: directory, binaryDirectories: [], applicationDirectories: [])
        let command = try builder.command(configurationPaths: ClaudeConfigurationPaths(environment: [:], homeDirectory: directory, selectedDirectory: profile))
        XCTAssertEqual(command, "/usr/bin/env -u CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CONFIG_DIR=" + ClaudeLoginCommandBuilder.shellQuote(profile.path) + " USER='synthetic-user' " + ClaudeLoginCommandBuilder.shellQuote(executable.path) + " auth login")
        XCTAssertTrue(command.contains("'\\''"))
    }

    func testDefaultLoginClearsInheritedProfileOverridesIncludingExplicitDefaultPath() throws {
        for explicitDefault in [false, true] {
            try assertSyntheticLoginEnvironment(customProfile: nil, explicitDefault: explicitDefault)
        }
    }

    func testCustomLoginKeepsSelectedProfileButClearsInheritedSecureStorageOverride() throws {
        try assertSyntheticLoginEnvironment(customProfile: "/synthetic/work ' $(never-run)", explicitDefault: false)
    }

    func testPreviousDejavuLoginExplicitlySelectsOnlyDefaultProfileAndPinsAccount() throws {
        try assertSyntheticLoginEnvironment(customProfile: nil, explicitDefault: false, credentialIdentity: .previousDejavuDefault)
    }

    func testPreviousDejavuLoginRejectsCustomProfileBeforeDiscoveringOrLaunchingCLI() {
        let home = URL(fileURLWithPath: "/synthetic/user")
        let builder = ClaudeLoginCommandBuilder(environment: [:], homeDirectory: home, binaryDirectories: [], applicationDirectories: [])
        let paths = ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/synthetic/custom"], homeDirectory: home)
        XCTAssertThrowsError(try builder.command(configurationPaths: paths, credentialIdentity: .previousDejavuDefault)) { error in
            XCTAssertEqual(error as? ClaudeLoginCommandError, .unsupportedCredentialIdentity)
        }
    }

    func testCredentialAccountMatchesOfficialCLIEnvironmentAndFallbackRules() {
        let cases: [([String: String], String, String)] = [
            ([:], "synthetic-user", "synthetic-user"),
            (["USER": ""], "synthetic-user", "synthetic-user"),
            (["USER": "configured.user_1-2"], "ignored", "configured.user_1-2"),
            (["USER": "wrong user"], "ignored", "claude-code-user"),
            (["USER": "$(never-run)"], "ignored", "claude-code-user"),
            (["USER": "user\n"], "ignored", "claude-code-user"),
            (["USER": "user\r"], "ignored", "claude-code-user"),
            (["USER": "user\r\n"], "ignored", "claude-code-user"),
            (["USER": "user\u{2028}"], "ignored", "claude-code-user"),
            ([:], "사용자", "claude-code-user")
        ]
        for (environment, userName, expected) in cases {
            XCTAssertEqual(ClaudeCredentialAccount.resolve(environment: environment, userName: userName), expected)
        }
    }

    func testCustomProfileCannotReadDefaultKeychainCredential() {
        let home = URL(fileURLWithPath: "/synthetic/home")
        let paths = ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/synthetic/custom"], homeDirectory: home)
        let reader = MacOSClaudeKeychainCredentialReader(configurationPaths: paths, homeDirectory: home)
        XCTAssertThrowsError(try reader.readCredential()) { error in
            XCTAssertEqual(error as? ClaudeExtendedUsageError, .credentialUnavailable)
        }
    }

    private func assertSyntheticLoginEnvironment(customProfile: String?, explicitDefault: Bool, credentialIdentity: ClaudeCredentialIdentity = .standard) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-claude-login-env-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("synthetic-claude")
        // This fixture only echoes its environment and arguments. It never
        // invokes the installed CLI, credentials, a browser or any network.
        let script = "#!/bin/sh\nprintf '%s|%s|%s|%s|%s' \"${CLAUDE_CONFIG_DIR-unset}\" \"${CLAUDE_SECURESTORAGE_CONFIG_DIR-unset}\" \"$USER\" \"$1\" \"$2\"\n"
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let environment = explicitDefault ? ["CLAUDE_CONFIG_DIR": directory.appendingPathComponent(".claude").path] : [:]
        let paths = ClaudeConfigurationPaths(
            environment: environment,
            homeDirectory: directory,
            selectedDirectory: customProfile.map { URL(fileURLWithPath: $0) }
        )
        let builder = ClaudeLoginCommandBuilder(environment: ["CLAUDE_CODE_PATH": executable.path, "USER": "synthetic-user"], homeDirectory: directory, binaryDirectories: [], applicationDirectories: [])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", try builder.command(configurationPaths: paths, credentialIdentity: credentialIdentity)]
        process.environment = ["CLAUDE_CONFIG_DIR": "/synthetic/unrelated", "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/synthetic/unrelated-credentials", "USER": "unrelated-account"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let expectedProfile = credentialIdentity == .previousDejavuDefault ? paths.directoryURL.path : (customProfile ?? "unset")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), expectedProfile + "|unset|synthetic-user|auth|login")
    }
}
