import Foundation
import XCTest

final class FixturePrivacyTests: XCTestCase {
    func testCanonicalFixturesContainNoSensitiveOrConversationFields() throws {
        let fixtureNames = try FixtureSupport.jsonFixtureNames()
        XCTAssertFalse(fixtureNames.isEmpty)
        let forbiddenFragments = [
            "accesstoken",
            "access_token",
            "token",
            "authorization",
            "bearer ",
            "accountid",
            "account_id",
            "session_id",
            "prompt_id",
            "prompt",
            "transcript",
            "conversation",
            "thread",
            "turn",
            "message",
            "messagebody",
            "workspace",
            "repository",
            "current_dir",
            "project_dir",
            "cwd",
            "authurl",
            "auth_url",
            "://",
            "?"
        ]

        for name in fixtureNames {
            let text = try XCTUnwrap(String(
                data: FixtureSupport.data(named: name),
                encoding: .utf8
            )).lowercased()
            for fragment in forbiddenFragments {
                XCTAssertFalse(text.contains(fragment), "\(name) contains forbidden fragment \(fragment)")
            }
        }
    }
}
