import Foundation
import XCTest
import DejavuDomain
@testable import DejavuPersistence

final class DiagnosticsEventLogTests: XCTestCase {
    func testWritesOnlyClosedAllowListedFieldsWithPrivatePermissions() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = DiagnosticsEventLog(directoryURL: directory)

        try await log.append(
            DiagnosticsEvent(
                recordedAt: Date(timeIntervalSince1970: 1_000),
                kind: .refreshCompleted,
                status: .ready
            )
        )

        let data = try Data(contentsOf: log.logURL)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data.dropLast()) as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["kind", "recordedAt", "status"])
        XCTAssertEqual(object["kind"] as? String, "refreshCompleted")
        let permissions = try FileManager.default.attributesOfItem(atPath: log.logURL.path)[
            .posixPermissions
        ] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testRotatesBeforeExceedingMaximumAndKeepsOnePreviousFile() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = DiagnosticsEvent(
            recordedAt: Date(timeIntervalSince1970: 1_000),
            kind: .refreshCompleted,
            status: .ready
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let lineSize = try encoder.encode(event).count + 1
        let log = DiagnosticsEventLog(directoryURL: directory, maximumBytes: lineSize * 2)

        try await log.append(event)
        try await log.append(event)
        try await log.append(event)

        XCTAssertLessThanOrEqual(try Data(contentsOf: log.logURL).count, lineSize * 2)
        XCTAssertEqual(try Data(contentsOf: log.previousLogURL).count, lineSize * 2)
    }

    func testRejectsSymlinkWithoutTouchingDestination() async throws {
        let directory = temporaryDirectory()
        let external = directory.deletingLastPathComponent()
            .appendingPathComponent("external-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: external)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: external)
        let log = DiagnosticsEventLog(directoryURL: directory)
        try FileManager.default.createSymbolicLink(at: log.logURL, withDestinationURL: external)

        do {
            try await log.append(
                DiagnosticsEvent(recordedAt: Date(), kind: .appStarted)
            )
            XCTFail("Expected the symlink to be rejected")
        } catch DiagnosticsEventLogError.unsafeFile {
            // Expected.
        }
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "keep")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "dejavu-diagnostics-log-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
