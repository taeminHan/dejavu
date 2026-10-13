import Foundation
import CryptoKit
import Security
import DejavuApplication
import DejavuDomain

public enum ClaudeExtendedUsageError: Error, Sendable, Equatable {
    case credentialUnavailable
    case credentialExpired
    case tokenRefreshPending
    case accessDenied
    case unauthorized
    case rateLimited(retryAt: Date?)
    case offline
    case serverError
    case invalidResponse
    case responseTooLarge
}

public actor ClaudeExtendedAccessPolicy {
    private var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func setEnabled(_ enabled: Bool) {
        guard !Task.isCancelled else { return }
        self.enabled = enabled
    }

    public func isEnabled() -> Bool { enabled }
}

public protocol ClaudeCredentialReading: Sendable {
    func readCredential() throws -> Data
}

enum ClaudeKeychainLookupResult: Sendable {
    case credential(Data)
    case notFound
    case accessDenied
    case unavailable
}

/// Reads the Claude Code credential item only after the app's explicit Fable
/// setting has enabled this provider. The returned bytes are never persisted or
/// logged by Dejavu.
public struct MacOSClaudeKeychainCredentialReader: ClaudeCredentialReading {
    public static let defaultService = "Claude Code-credentials"

    private let service: String
    private let profileIsSupported: Bool
    private let account: String
    private let lookup: @Sendable (String, String) -> ClaudeKeychainLookupResult

    public init(
        credentialIdentity: ClaudeCredentialIdentity = .standard,
        configurationPaths: ClaudeConfigurationPaths = ClaudeConfigurationPaths(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let environment = ProcessInfo.processInfo.environment
        self.init(
            credentialIdentity: credentialIdentity,
            configurationPaths: configurationPaths,
            homeDirectory: homeDirectory,
            account: ClaudeCredentialAccount.resolve(environment: environment, userName: NSUserName()),
            secureStorageOverrideIsSupported: environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"].map(\.isEmpty) ?? true,
            lookup: Self.lookupCredential
        )
    }

    init(
        credentialIdentity: ClaudeCredentialIdentity = .standard,
        configurationPaths: ClaudeConfigurationPaths,
        homeDirectory: URL,
        account: String,
        secureStorageOverrideIsSupported: Bool = true,
        lookup: @escaping @Sendable (String, String) -> ClaudeKeychainLookupResult
    ) {
        self.lookup = lookup
        self.account = account
        // Custom profiles can have a different credential identity. Until its
        // official service is explicitly known, never read the default user's
        // item and accidentally display another profile's usage.
        profileIsSupported = secureStorageOverrideIsSupported
            && configurationPaths.directoryURL == homeDirectory.appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
        // Previous Dejavu login commands explicitly set the default directory.
        // CLI 2.1.291 hashes this path (NFC, SHA-256, first 8 hex digits).
        // The user must select that exact identity. Never enumerate, copy,
        // delete, or fall back to any other item, even if this item is absent.
        switch credentialIdentity {
        case .standard: service = Self.defaultService
        case .previousDejavuDefault: service = Self.legacyDefaultService(homeDirectory: homeDirectory)
        }
    }

    public func readCredential() throws -> Data {
        guard profileIsSupported else { throw ClaudeExtendedUsageError.credentialUnavailable }
        switch lookup(service, account) {
        case let .credential(data):
            guard !data.isEmpty else { throw ClaudeExtendedUsageError.credentialUnavailable }
            return data
        case .accessDenied:
            throw ClaudeExtendedUsageError.accessDenied
        case .notFound, .unavailable:
            throw ClaudeExtendedUsageError.credentialUnavailable
        }
    }

    static func legacyDefaultService(homeDirectory: URL) -> String {
        let path = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
            .standardizedFileURL.path.precomposedStringWithCanonicalMapping
        let hash = SHA256.hash(data: Data(path.utf8)).prefix(4)
            .map { String(format: "%02x", $0) }.joined()
        return defaultService + "-" + hash
    }

    private static func lookupCredential(service: String, account: String) -> ClaudeKeychainLookupResult {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return .unavailable }
            return .credential(data)
        case errSecItemNotFound:
            return .notFound
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .accessDenied
        default:
            return .unavailable
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

    private let credentialReaderFactory: @Sendable (ClaudeCredentialIdentity) -> any ClaudeCredentialReading
    private let requestOperation: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let endpoint: URL
    private let now: @Sendable () -> Date
    private let userAgent: String
    private var retryDeadline: ContinuousClock.Instant?
    private var credentialIdentity: ClaudeCredentialIdentity
    private var credentialGeneration: UInt64 = 0
    private var activeRequests: [UUID: Task<(Data, URLResponse), Error>] = [:]

    public init(
        credentialReader: (any ClaudeCredentialReading)? = nil,
        credentialReaderFactory: @escaping @Sendable (ClaudeCredentialIdentity) -> any ClaudeCredentialReading = {
            MacOSClaudeKeychainCredentialReader(credentialIdentity: $0)
        },
        credentialIdentity: ClaudeCredentialIdentity = .standard,
        session: URLSession? = nil,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        now: @escaping @Sendable () -> Date = { Date() },
        userAgent: String = "claude-code/2.1.170"
    ) {
        let factory: @Sendable (ClaudeCredentialIdentity) -> any ClaudeCredentialReading
        if let credentialReader {
            factory = { _ in credentialReader }
        } else {
            factory = credentialReaderFactory
        }
        let requestSession: URLSession
        if let session {
            requestSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            requestSession = URLSession(configuration: configuration)
        }
        self.init(
            credentialReaderFactory: factory,
            credentialIdentity: credentialIdentity,
            requestOperation: { try await requestSession.data(for: $0) },
            endpoint: endpoint,
            now: now,
            userAgent: userAgent
        )
    }

    init(
        credentialReaderFactory: @escaping @Sendable (ClaudeCredentialIdentity) -> any ClaudeCredentialReading,
        credentialIdentity: ClaudeCredentialIdentity = .standard,
        requestOperation: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        endpoint: URL = URL(string: "https://synthetic.invalid/usage")!,
        now: @escaping @Sendable () -> Date = { Date() },
        userAgent: String = "dejavu-synthetic-transport"
    ) {
        self.credentialReaderFactory = credentialReaderFactory
        self.credentialIdentity = credentialIdentity
        self.requestOperation = requestOperation
        self.endpoint = endpoint
        self.now = now
        self.userAgent = userAgent
    }

    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        try Task.checkCancellation()
        let generation = credentialGeneration
        if let retryDeadline, ContinuousClock.now < retryDeadline {
            let remaining = ContinuousClock.now.duration(to: retryDeadline).components
            throw ClaudeExtendedUsageError.rateLimited(
                retryAt: now().addingTimeInterval(Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
            )
        }
        let request = try makeRequest(credentialReader: credentialReaderFactory(credentialIdentity))
        try Task.checkCancellation()
        let identifier = UUID()
        let requestOperation = self.requestOperation
        let requestTask = Task { try await requestOperation(request) }
        activeRequests[identifier] = requestTask
        defer { activeRequests.removeValue(forKey: identifier) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withTaskCancellationHandler {
                try await requestTask.value
            } onCancel: {
                requestTask.cancel()
            }
        } catch {
            try checkCurrentCredentialGeneration(generation)
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? URLError,
               [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed, .timedOut].contains(error.code) {
                throw ClaudeExtendedUsageError.offline
            }
            throw ClaudeExtendedUsageError.invalidResponse
        }
        try checkCurrentCredentialGeneration(generation)

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
            let retryAt = Self.retryDate(from: http, now: now()) ?? now().addingTimeInterval(60)
            retryDeadline = ContinuousClock.now.advanced(by: .seconds(max(60, min(1800, retryAt.timeIntervalSince(now())))))
            throw ClaudeExtendedUsageError.rateLimited(
                retryAt: now().addingTimeInterval(max(60, min(1800, retryAt.timeIntervalSince(now()))))
            )
        case 500...599:
            throw ClaudeExtendedUsageError.serverError
        default:
            throw ClaudeExtendedUsageError.invalidResponse
        }

        do {
            return try ClaudeOAuthUsageParser().parse(data, capturedAt: now())
        } catch {
            throw ClaudeExtendedUsageError.invalidResponse
        }
    }

    /// Explicit user refresh or completed official login may try once before
    /// the normal backoff. Periodic refresh never calls this method.
    public func resetRetryBackoff() { retryDeadline = nil }

    public var currentCredentialIdentity: ClaudeCredentialIdentity { credentialIdentity }

    /// Changes only which exact local identity may be read. No Keychain or
    /// network access occurs until a subsequent consented fetch. Owned requests
    /// are cancelled and all late results/errors are invalidated by generation.
    public func setCredentialIdentity(_ identity: ClaudeCredentialIdentity) {
        guard !Task.isCancelled, credentialIdentity != identity else { return }
        credentialIdentity = identity
        credentialGeneration &+= 1
        retryDeadline = nil
        for task in activeRequests.values { task.cancel() }
        activeRequests.removeAll()
    }

    private func checkCurrentCredentialGeneration(_ generation: UInt64) throws {
        guard generation == credentialGeneration else { throw CancellationError() }
        try Task.checkCancellation()
    }

    private func makeRequest(credentialReader: any ClaudeCredentialReading) throws -> URLRequest {
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
            if let refreshToken = credential.oauth?.refreshToken, !refreshToken.isEmpty,
               credential.oauth?.refreshTokenExpiresAt.map({ Date(timeIntervalSince1970: TimeInterval($0) / 1_000) > now() }) ?? true {
                throw ClaudeExtendedUsageError.tokenRefreshPending
            }
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
            // The shared status-line file has no credential-identity tag. It
            // cannot safely replace the selected OAuth identity's result.
            throw Self.providerFailure(for: error)
        }
    }

    private static func providerFailure(for error: Error) -> UsageProviderFailure {
        guard let failure = error as? ClaudeExtendedUsageError else { return .failed }
        switch failure {
        case .credentialUnavailable, .credentialExpired, .unauthorized:
            return .loginRequired
        case .accessDenied:
            return .permissionDenied
        case let .rateLimited(retryAt):
            return .rateLimited(retryAt: retryAt)
        case .offline:
            return .offline
        case .tokenRefreshPending:
            return .tokenRefreshPending
        case .serverError:
            return .serverFailed
        case .invalidResponse, .responseTooLarge:
            return .responseChanged
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
    let refreshToken: String?
    let refreshTokenExpiresAt: Int64?
}
