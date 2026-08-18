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

public actor ClaudeExtendedAccessPolicy {
    private var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }

    public func isEnabled() -> Bool { enabled }
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
            || error.code == .dnsLookupFailed {
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

public struct ClaudeCombinedUsageProvider: UsageProviding, Sendable {
    private let statusLineProvider: ClaudeStatusSnapshotProvider
    private let extendedProvider: any ClaudeOAuthUsageRequesting
    private let accessPolicy: ClaudeExtendedAccessPolicy

    public init(
        statusLineProvider: ClaudeStatusSnapshotProvider,
        extendedProvider: any ClaudeOAuthUsageRequesting = ClaudeOAuthUsageClient(),
        accessPolicy: ClaudeExtendedAccessPolicy
    ) {
        self.statusLineProvider = statusLineProvider
        self.extendedProvider = extendedProvider
        self.accessPolicy = accessPolicy
    }

    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        guard await accessPolicy.isEnabled() else {
            return try await statusLineProvider.fetchUsage()
        }

        do {
            return try await extendedProvider.fetchUsage()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            do {
                return try await statusLineProvider.fetchUsage()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw Self.providerFailure(for: error)
            }
        }
    }

    private static func providerFailure(for error: Error) -> UsageProviderFailure {
        guard let failure = error as? ClaudeExtendedUsageError else { return .failed }
        switch failure {
        case .credentialUnavailable, .credentialExpired, .unauthorized:
            return .loginRequired
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
