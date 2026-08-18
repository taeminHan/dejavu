import Foundation
import XCTest
@testable import DejavuProviders

final class CodexExecutableLocatorTests: XCTestCase {
    func testExecutableOverrideWinsAndReturnsCanonicalSymlinkTarget() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("native-codex")
        try makeExecutable(at: target)
        let link = root.appendingPathComponent("codex-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let homeCandidate = root.appendingPathComponent("home/.local/bin/codex")
        try makeExecutable(at: homeCandidate)
        let locator = CodexExecutableLocator(
            environment: ["CODEX_CLI_PATH": link.path, "PATH": ""],
            homeDirectory: root.appendingPathComponent("home", isDirectory: true),
            systemBinaryDirectories: [],
            applicationDirectories: []
        )

        XCTAssertEqual(locator.locate(), target.resolvingSymlinksInPath())
    }

    func testInvalidOverrideFallsBackToKnownHomeCandidate() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let expected = home.appendingPathComponent(".local/bin/codex")
        try makeExecutable(at: expected)

        let locator = CodexExecutableLocator(
            environment: [
                "CODEX_CLI_PATH": root.appendingPathComponent("missing").path,
                "PATH": ""
            ],
            homeDirectory: home,
            systemBinaryDirectories: [],
            applicationDirectories: []
        )

        XCTAssertEqual(locator.locate(), expected)
    }

    func testNVMVersionsUseNumericNewestFirstAndSearchIsBounded() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let old = home.appendingPathComponent(".nvm/versions/node/v9.9.0/bin/codex")
        let newest = home.appendingPathComponent(".nvm/versions/node/v10.0.0/bin/codex")
        try makeExecutable(at: old)
        try makeExecutable(at: newest)

        let locator = CodexExecutableLocator(
            environment: ["PATH": ""],
            homeDirectory: home,
            systemBinaryDirectories: [],
            applicationDirectories: []
        )

        XCTAssertEqual(locator.locate(), newest)
    }

    func testDirectoryAndNonExecutableFileAreRejected() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let candidate = home.appendingPathComponent(".local/bin/codex")
        try FileManager.default.createDirectory(
            at: candidate.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: candidate)

        let locator = CodexExecutableLocator(
            environment: ["PATH": candidate.deletingLastPathComponent().path],
            homeDirectory: home,
            systemBinaryDirectories: [],
            applicationDirectories: []
        )

        XCTAssertNil(locator.locate())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-codex-locator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }
}
