import Foundation
import DejavuApplication
import DejavuDomain

/// Application-facing Codex provider. It resolves the local CLI for every
/// fetch so package-manager upgrades and newly installed CLIs are discovered
/// without retaining an obsolete executable path.
public actor CodexUsageProvider: UsageProviding {
    private let locator: CodexExecutableLocator
    private let configuration: CodexAppServerConfiguration
    private let clientFactory: @Sendable (URL, CodexAppServerConfiguration) -> CodexAppServerClient

    private var activeClient: CodexAppServerClient?
    private var isShutDown = false
    private var loginRequiredWasUnauthorized: Bool?

    public init(
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        configuration: CodexAppServerConfiguration = CodexAppServerConfiguration()
    ) {
        self.locator = locator
        self.configuration = configuration
        clientFactory = { executableURL, configuration in
            CodexAppServerClient(
                executableURL: executableURL,
                configuration: configuration
            )
        }
    }

    init(
        locator: CodexExecutableLocator,
        configuration: CodexAppServerConfiguration,
        clientFactory: @escaping @Sendable (
            URL,
            CodexAppServerConfiguration
        ) -> CodexAppServerClient
    ) {
        self.locator = locator
        self.configuration = configuration
        self.clientFactory = clientFactory
    }

    public func fetchUsage() async throws -> CodexUsageSnapshot {
        guard !isShutDown else { throw UsageProviderFailure.unavailable }
        guard activeClient == nil else { throw UsageProviderFailure.failed }
        guard let executableURL = locator.locate() else {
            throw UsageProviderFailure.unavailable
        }

        let client = clientFactory(executableURL, configuration)
        activeClient = client

        do {
            let snapshot = try await client.fetchUsage()
            loginRequiredWasUnauthorized = nil
            clearActiveClient(client)
            guard !isShutDown else { throw CancellationError() }
            return snapshot
        } catch is CancellationError {
            clearActiveClient(client)
            throw CancellationError()
        } catch {
            clearActiveClient(client)
            guard !isShutDown else { throw CancellationError() }
            let failure = Self.providerFailure(for: error)
            if failure == .loginRequired {
                loginRequiredWasUnauthorized = (error as? CodexAppServerError) == .unauthorized
            } else if let wasUnauthorized = loginRequiredWasUnauthorized {
                if (error as? CodexAppServerError) == .backendFailed, !wasUnauthorized {
                    loginRequiredWasUnauthorized = nil
                } else {
                    throw UsageProviderFailure.loginRequired
                }
            }
            throw failure
        }
    }

    /// Stops only the child owned by the current request and permanently
    /// prevents this provider instance from starting another one.
    public func shutdown() async {
        isShutDown = true
        guard let activeClient else { return }
        await activeClient.shutdown()
        clearActiveClient(activeClient)
    }

    /// A successful explicit login permits the follow-up read to settle the
    /// new state rather than carrying an earlier login-required failure.
    public func authenticationCompleted() { loginRequiredWasUnauthorized = nil }

    private func clearActiveClient(_ client: CodexAppServerClient) {
        if let activeClient, activeClient === client {
            self.activeClient = nil
        }
    }

    private static func providerFailure(for error: Error) -> UsageProviderFailure {
        guard let error = error as? CodexAppServerError else { return .failed }
        switch error {
        case .loginRequired, .unauthorized:
            return .loginRequired
        case .launchFailed, .shutDown:
            return .unavailable
        case .timedOut:
            return .offline
        case .requestInProgress,
             .transportFailure,
             .responseTooLarge,
             .malformedResponse,
             .initializationRejected,
             .accountReadRejected,
             .invalidAccountResponse,
             .rateLimitsRejected,
             .invalidRateLimitsResponse,
             .serverExited,
             .backendFailed,
             .loginRejected,
             .invalidLoginResponse:
            return .failed
        }
    }
}
