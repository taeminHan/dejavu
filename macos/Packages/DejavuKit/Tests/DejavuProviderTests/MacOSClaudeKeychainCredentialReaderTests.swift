import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class MacOSClaudeKeychainCredentialReaderTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/synthetic/user")
    private let defaultService = MacOSClaudeKeychainCredentialReader.defaultService
    private let legacyService = "Claude Code-credentials-e104ad58"
    private let account = "synthetic-user"

    func testLegacyServiceMatchesOfficialCLIExplicitDefaultPathFixture() {
        // CLI 2.1.291 VN("-credentials"): NFC config path, SHA-256 hex,
        // substring(0, 8). Independently derived with Node crypto fixtures.
        XCTAssertEqual(MacOSClaudeKeychainCredentialReader.legacyDefaultService(homeDirectory: home), legacyService)
        let composed = URL(fileURLWithPath: "/synthetic/café")
        let decomposed = URL(fileURLWithPath: "/synthetic/cafe\u{301}")
        XCTAssertEqual(MacOSClaudeKeychainCredentialReader.legacyDefaultService(homeDirectory: composed), "Claude Code-credentials-2530a4da")
        XCTAssertEqual(MacOSClaudeKeychainCredentialReader.legacyDefaultService(homeDirectory: decomposed), "Claude Code-credentials-2530a4da")
    }

    func testExistingDefaultCredentialAlwaysWinsWithoutReadingLegacyItem() throws {
        let data = Data("synthetic-default-credential".utf8)
        let lookup = SyntheticKeychainLookup(items: [defaultService: .credential(data), legacyService: .credential(Data("synthetic-legacy".utf8))])
        XCTAssertEqual(try reader(lookup).readCredential(), data)
        XCTAssertEqual(lookup.services(), [defaultService])
        XCTAssertEqual(lookup.accounts(), [account])
    }

    func testExplicitPreviousSelectionReadsOnlyExactLegacyDefaultIdentity() throws {
        let data = Data("synthetic-legacy-credential".utf8)
        let lookup = SyntheticKeychainLookup(items: [defaultService: .credential(Data("must-not-read".utf8)), legacyService: .credential(data)])
        XCTAssertEqual(try reader(lookup, identity: .previousDejavuDefault).readCredential(), data)
        XCTAssertEqual(lookup.services(), [legacyService])
        XCTAssertEqual(lookup.accounts(), [account])
    }

    func testMissingSelectedItemNeverAutomaticallyReadsOtherIdentity() {
        for identity in ClaudeCredentialIdentity.allCases {
            let selectedService = identity == .standard ? defaultService : legacyService
            let otherService = identity == .standard ? legacyService : defaultService
            let lookup = SyntheticKeychainLookup(items: [otherService: .credential(Data("must-not-read".utf8))])
            XCTAssertThrowsError(try reader(lookup, identity: identity).readCredential()) { error in
                XCTAssertEqual(error as? ClaudeExtendedUsageError, .credentialUnavailable)
            }
            XCTAssertEqual(lookup.services(), [selectedService])
            XCTAssertEqual(lookup.accounts(), [account])
        }
    }

    func testNoOtherProfileOrServiceIsQueriedWhenBothAllowedItemsAreMissing() {
        let lookup = SyntheticKeychainLookup(items: ["Claude Code-credentials-other-profile": .credential(Data("must-not-read".utf8))])
        XCTAssertThrowsError(try reader(lookup).readCredential()) { error in
            XCTAssertEqual(error as? ClaudeExtendedUsageError, .credentialUnavailable)
        }
        XCTAssertEqual(lookup.services(), [defaultService])
    }

    func testDeniedUnavailableAndEmptyDefaultItemsNeverFallBack() {
        let cases: [(ClaudeKeychainLookupResult, ClaudeExtendedUsageError)] = [
            (.accessDenied, .accessDenied),
            (.unavailable, .credentialUnavailable),
            (.credential(Data()), .credentialUnavailable)
        ]
        for (result, expected) in cases {
            let lookup = SyntheticKeychainLookup(items: [defaultService: result, legacyService: .credential(Data("must-not-read".utf8))])
            XCTAssertThrowsError(try reader(lookup).readCredential()) { error in
                XCTAssertEqual(error as? ClaudeExtendedUsageError, expected)
            }
            XCTAssertEqual(lookup.services(), [defaultService])
        }
    }

    func testExistingMalformedOrExpiredDefaultCredentialDoesNotSelectAnotherAccount() throws {
        for data in [Data("not-json".utf8), Data(#"{"claudeAiOauth":{"accessToken":"synthetic-expired","expiresAt":1000}}"#.utf8)] {
            let lookup = SyntheticKeychainLookup(items: [defaultService: .credential(data), legacyService: .credential(Data("must-not-read".utf8))])
            XCTAssertEqual(try reader(lookup).readCredential(), data)
            XCTAssertEqual(lookup.services(), [defaultService])
        }
    }

    func testCustomProfileFailsClosedWithoutAnyKeychainLookup() {
        for identity in ClaudeCredentialIdentity.allCases {
            let lookup = SyntheticKeychainLookup(items: [defaultService: .credential(Data("must-not-read".utf8))])
            let paths = ClaudeConfigurationPaths(environment: ["CLAUDE_CONFIG_DIR": "/synthetic/custom"], homeDirectory: home)
            let reader = MacOSClaudeKeychainCredentialReader(credentialIdentity: identity, configurationPaths: paths, homeDirectory: home, account: account, lookup: lookup.read)
            XCTAssertThrowsError(try reader.readCredential()) { error in
                XCTAssertEqual(error as? ClaudeExtendedUsageError, .credentialUnavailable)
            }
            XCTAssertEqual(lookup.services(), [])
        }
    }

    func testCustomSecureStorageOverrideFailsClosedWithoutAnyKeychainLookup() {
        for identity in ClaudeCredentialIdentity.allCases {
            let lookup = SyntheticKeychainLookup(items: [defaultService: .credential(Data("must-not-read".utf8))])
            let reader = MacOSClaudeKeychainCredentialReader(
                credentialIdentity: identity,
                configurationPaths: ClaudeConfigurationPaths(environment: [:], homeDirectory: home),
                homeDirectory: home,
                account: account,
                secureStorageOverrideIsSupported: false,
                lookup: lookup.read
            )
            XCTAssertThrowsError(try reader.readCredential()) { error in
                XCTAssertEqual(error as? ClaudeExtendedUsageError, .credentialUnavailable)
            }
            XCTAssertEqual(lookup.services(), [])
        }
    }

    func testExactAccountLookupNeverReadsAnotherAccountsDefaultItem() throws {
        let expectedData = Data("synthetic-correct-account".utf8)
        let reader = MacOSClaudeKeychainCredentialReader(
            configurationPaths: ClaudeConfigurationPaths(environment: [:], homeDirectory: home),
            homeDirectory: home,
            account: account,
            lookup: { service, account in
                guard service == "Claude Code-credentials" else { return .notFound }
                return account == "synthetic-user" ? .credential(expectedData) : .credential(Data("must-not-read".utf8))
            }
        )
        XCTAssertEqual(try reader.readCredential(), expectedData)
    }

    private func reader(_ lookup: SyntheticKeychainLookup, identity: ClaudeCredentialIdentity = .standard) -> MacOSClaudeKeychainCredentialReader {
        MacOSClaudeKeychainCredentialReader(credentialIdentity: identity, configurationPaths: ClaudeConfigurationPaths(environment: [:], homeDirectory: home), homeDirectory: home, account: account, lookup: lookup.read)
    }
}

private final class SyntheticKeychainLookup: @unchecked Sendable {
    private let lock = NSLock()
    private let items: [String: ClaudeKeychainLookupResult]
    private var queriedServices: [String] = []
    private var queriedAccounts: [String] = []

    init(items: [String: ClaudeKeychainLookupResult]) { self.items = items }

    func read(service: String, account: String) -> ClaudeKeychainLookupResult {
        lock.lock()
        defer { lock.unlock() }
        queriedServices.append(service)
        queriedAccounts.append(account)
        return items[service] ?? .notFound
    }

    func services() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return queriedServices
    }

    func accounts() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return queriedAccounts
    }
}
