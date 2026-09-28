import Foundation
import Security
import DejavuApplication
import DejavuDomain

public enum ClaudeExtendedUsageError: Error, Sendable, Equatable {
    case credentialUnavailable
    case credentialExpired
    case accessDenied
    case unauthorized
    case rateLimited(retryAt: Date?)
    case offline
    case invalidResponse
    case responseTooLarge
}

/// The latest opt-in Fable read, kept only as a classification so the UI can
/// explain a Keychain approval or an expired Claude Code sign-in. It never
/// carries credential bytes, response bodies, or account identifiers.
public enum ClaudeExtendedAccessOutcome: Sendable, Equatable {
    case connected
    case failed(ClaudeExtendedUsageError)
}

public actor ClaudeExtendedAccessPolicy {
    private var enabled: Bool
    private var outcome: ClaudeExtendedAccessOutcome?

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func setEnabled(_ enabled: Bool) {
        if self.enabled != enabled {
            outcome = nil
        }
        self.enabled = enabled
    }

    public func isEnabled() -> Bool { enabled }

    /// `nil` while the extended connection is off or before its first read
    /// after being turned on has finished.
    public func latestOutcome() -> ClaudeExtendedAccessOutcome? {
        enabled ? outcome : nil
    }

    func record(_ outcome: ClaudeExtendedAccessOutcome) {
        guard enabled else { return }
        self.outcome = outcome
    }
}

public protocol ClaudeCredentialReading: Sendable {
    func readCredential() throws -> Data
}

/// Reads the Claude Code credential item only after the app's explicit Fable
/// setting has enabled this provider. The returned bytes are never persisted or
/// logged by Dejavu.
public struct MacOSClaudeKeychainCredentialReader: ClaudeCredentialReading {
    public static let defaultService = "Claude Code-credentials"

    private let service: String

    public init(service: String = Self.defaultService) {
        self.service = service
    }

    public func readCredential() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, !data.isEmpty else {
                throw ClaudeExtendedUsageError.credentialUnavailable
            }
            return data
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            throw ClaudeExtendedUsageError.accessDenied
        default:
            throw ClaudeExtendedUsageError.credentialUnavailable
        }
    }
}

public protocol ClaudeOAuthUsageRequesting: Sendable {
    func fetchUsage() async throws -> ClaudeUsageSnapshot
}

/// Optional, user-enabled provider for Fable's model-scoped weekly limit.
/// Anthropic does not document this endpoint as a third-party API, so it is
/// isolated from the default status-line integration and fails closed.
public actor ClaudeOAuthUsageClient: ClaudeOAuthUsageRequesting {
    public static let maximumResponseBytes = 512 * 1_024

    private let credentialReader: any ClaudeCredentialReading
    private let session: URLSession
    private let endpoint: URL
    private let now: @Sendable () -> Date
    private let userAgent: String

    public init(
        credentialReader: any ClaudeCredentialReading = MacOSClaudeKeychainCredentialReader(),
        session: URLSession? = nil,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        now: @escaping @Sendable () -> Date = { Date() },
        userAgent: String = "claude-code/2.1.170"
    ) {
        self.credentialReader = credentialReader
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            self.session = URLSession(configuration: configuration)
        }
        self.endpoint = endpoint
        self.now = now
        self.userAgent = userAgent
    }

    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        let request = try makeRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .notConnectedToInternet
            || error.code == .networkConnectionLost
            || error.code == .cannotConnectToHost
            || error.code == .dnsLookupFailed
            || error.code == .cannotFindHost
            || error.code == .timedOut
            || error.code == .secureConnectionFailed
            || error.code == .internationalRoamingOff
            || error.code == .dataNotAllowed {
            // Transient network conditions (sleep, captive Wi-Fi, a slow
            // link) are not a changed interface.
            throw ClaudeExtendedUsageError.offline
        } catch {
            throw ClaudeExtendedUsageError.invalidResponse
        }

        guard data.count <= Self.maximumResponseBytes else {
            throw ClaudeExtendedUsageError.responseTooLarge
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClaudeExtendedUsageError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw ClaudeExtendedUsageError.unauthorized
        case 429:
            throw ClaudeExtendedUsageError.rateLimited(
                retryAt: Self.retryDate(from: http, now: now())
            )
        case 500..<600:
            // A server-side failure means Claude could not be reached for
            // this check, not that the interface changed.
            throw ClaudeExtendedUsageError.offline
        default:
            throw ClaudeExtendedUsageError.invalidResponse
        }

        do {
            return try ClaudeOAuthUsageParser().parse(data, capturedAt: now())
        } catch {
            throw ClaudeExtendedUsageError.invalidResponse
        }
    }

    private func makeRequest() throws -> URLRequest {
        // Keep both the decoded envelope and token inside this short scope so
        // no actor property or persisted object can retain credential bytes.
        let credentialData = try credentialReader.readCredential()
        let credential: CredentialEnvelope
        do {
            credential = try JSONDecoder().decode(CredentialEnvelope.self, from: credentialData)
        } catch {
            throw ClaudeExtendedUsageError.credentialUnavailable
        }

        guard let token = credential.oauth?.accessToken, !token.isEmpty else {
            throw ClaudeExtendedUsageError.credentialUnavailable
        }
        if let expiresAt = credential.oauth?.expiresAt,
           Date(timeIntervalSince1970: TimeInterval(expiresAt) / 1_000) <= now().addingTimeInterval(15) {
            throw ClaudeExtendedUsageError.credentialExpired
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func retryDate(from response: HTTPURLResponse, now: Date) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }
}

/// Reads Claude usage from the first source that has current data:
///
/// 1. the opt-in extended connection (only while the user has enabled it),
/// 2. the user-connected Claude Code status-line bridge snapshot,
/// 3. Claude Desktop's local usage history (read-only; no Fable, no resets).
///
/// A status-line snapshot captured within its no-reset window is returned
/// directly. An older one keeps each limit until its reset, which can be days
/// away, so Desktop history is also read and its sample wins when it is newer
/// than the status-line capture; the status line wins a tie. Desktop history
/// is otherwise used when the preceding sources failed. When every source
/// fails, the extended failure is reported first, then the status-line
/// failure. A Desktop history failure never replaces either, except that a
/// history file without a usable sample turns a missing status line's
/// "login required" into "unavailable": Desktop is closed or idle, which is
/// not a lost sign-in.
public struct ClaudeCombinedUsageProvider: UsageProviding, Sendable {
    private let statusLineProvider: ClaudeStatusSnapshotProvider
    private let desktopHistoryProvider: ClaudeDesktopHistoryProvider?
    private let extendedProvider: any ClaudeOAuthUsageRequesting
    private let accessPolicy: ClaudeExtendedAccessPolicy

    public init(
        statusLineProvider: ClaudeStatusSnapshotProvider,
        desktopHistoryProvider: ClaudeDesktopHistoryProvider? = nil,
        extendedProvider: any ClaudeOAuthUsageRequesting = ClaudeOAuthUsageClient(),
        accessPolicy: ClaudeExtendedAccessPolicy
    ) {
        self.statusLineProvider = statusLineProvider
        self.desktopHistoryProvider = desktopHistoryProvider
        self.extendedProvider = extendedProvider
        self.accessPolicy = accessPolicy
    }

    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        var extendedFailure: UsageProviderFailure?

        if await accessPolicy.isEnabled() {
            do {
                let snapshot = try await extendedProvider.fetchUsage()
                await accessPolicy.record(.connected)
                return snapshot
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // URLSession reports task cancellation as a URL error, which
                // must not be recorded as a Fable failure or fall through.
                try Task.checkCancellation()
                let failure = (error as? ClaudeExtendedUsageError) ?? .invalidResponse
                await accessPolicy.record(.failed(failure))
                extendedFailure = Self.providerFailure(for: failure)
            }
        }

        var statusLineSnapshot: ClaudeUsageSnapshot?
        var statusLineFailure = UsageProviderFailure.failed
        do {
            statusLineSnapshot = try await statusLineProvider.fetchUsage()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            statusLineFailure = (error as? UsageProviderFailure) ?? .failed
        }

        // A status line captured within its no-reset window is current, even
        // while Claude Desktop also writes samples.
        if let statusLineSnapshot,
           statusLineProvider.now().timeIntervalSince(statusLineSnapshot.capturedAt)
               <= statusLineProvider.freshnessPolicy.maximumAgeWithoutReset {
            return statusLineSnapshot
        }

        if let desktopHistoryProvider {
            do {
                let desktopSnapshot = try await desktopHistoryProvider.fetchUsage(
                    now: desktopHistoryProvider.now()
                )
                // An older status-line snapshot keeps each limit until its
                // reset even when Claude Code has not run for days; a newer
                // Desktop sample is more current.
                if let statusLineSnapshot, statusLineSnapshot.capturedAt >= desktopSnapshot.capturedAt {
                    return statusLineSnapshot
                }
                return desktopSnapshot
            } catch is CancellationError {
                throw CancellationError()
            } catch ClaudeDesktopHistoryProviderError.historyUnavailable {
                // No Desktop history: the preceding reason stands.
            } catch {
                // Desktop history exists without a usable sample: Desktop is
                // closed or idle, which is not a lost sign-in.
                if statusLineFailure == .loginRequired {
                    statusLineFailure = .unavailable
                }
            }
        }

        if let statusLineSnapshot { return statusLineSnapshot }
        throw extendedFailure ?? statusLineFailure
    }

    private static func providerFailure(for failure: ClaudeExtendedUsageError) -> UsageProviderFailure {
        switch failure {
        case .credentialUnavailable, .unauthorized:
            return .loginRequired
        case .credentialExpired:
            // Claude Code renews an expired access token the next time it
            // runs; this is not a lost sign-in (Windows `TokenRefreshPending`).
            return .failed
        case .accessDenied:
            return .unavailable
        case let .rateLimited(retryAt):
            return .rateLimited(retryAt: retryAt)
        case .offline:
            return .offline
        case .invalidResponse, .responseTooLarge:
            return .failed
        }
    }
}

private struct CredentialEnvelope: Decodable {
    let oauth: OAuthCredential?

    enum CodingKeys: String, CodingKey {
        case oauth = "claudeAiOauth"
    }
}

private struct OAuthCredential: Decodable {
    let accessToken: String?
    let expiresAt: Int64?
}
