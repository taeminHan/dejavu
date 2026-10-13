import Foundation

/// Owns one user-requested login. Repeated requests reopen its existing URL;
/// they never create another callback server or retain the spent URL.
public actor CodexAuthenticationService {
    private let locator: CodexExecutableLocator
    private let configuration: CodexAppServerConfiguration
    private let clientFactory: @Sendable (URL, CodexAppServerConfiguration) -> CodexAppServerClient
    private var client: CodexAppServerClient?
    private var operation: Task<Void, Error>?
    private var authenticationURL: URL?
    private var operationID: UUID?
    private var cancellation: (id: UUID, task: Task<Void, Never>)?
    private var isShutDown = false

    public init(
        locator: CodexExecutableLocator = CodexExecutableLocator(),
        configuration: CodexAppServerConfiguration = CodexAppServerConfiguration(),
        clientFactory: @escaping @Sendable (URL, CodexAppServerConfiguration) -> CodexAppServerClient = {
            CodexAppServerClient(executableURL: $0, configuration: $1)
        }
    ) {
        self.locator = locator
        self.configuration = configuration
        self.clientFactory = clientFactory
    }

    public var isAuthenticating: Bool { operation != nil && cancellation == nil && !isShutDown }

    @discardableResult
    public func reopenBrowserIfPending(
        openBrowser: @escaping @Sendable (URL) async throws -> Void
    ) async throws -> Bool {
        guard operation != nil, cancellation == nil, !isShutDown else { return false }
        if let authenticationURL { try await openBrowser(authenticationURL) }
        return true
    }

    public func login(openBrowser: @escaping @Sendable (URL) async throws -> Void) async throws {
        try Task.checkCancellation()
        guard !isShutDown else { throw CodexAppServerError.shutDown }
        while let cancellation {
            await cancellation.task.value
            finishCancellation(id: cancellation.id)
            try Task.checkCancellation()
            guard !isShutDown else { throw CodexAppServerError.shutDown }
        }
        if let operation {
            if let authenticationURL { try await openBrowser(authenticationURL) }
            try await operation.value
            return
        }
        guard let executable = locator.locate() else { throw CodexAppServerError.launchFailed }
        let client = clientFactory(executable, configuration)
        self.client = client
        let id = UUID()
        operationID = id
        let operation = Task {
            try await client.authenticate(onCompletion: { await self.clearAuthenticationURL(for: id) }) { url in
                try await self.setAuthenticationURL(url, for: id)
                try Task.checkCancellation()
                try await openBrowser(url)
            }
        }
        self.operation = operation
        do {
            try await operation.value
            clearOperation(id: id)
        } catch {
            clearOperation(id: id)
            throw error
        }
    }

    public func cancel() async {
        if let cancellation {
            await cancellation.task.value
            finishCancellation(id: cancellation.id)
            return
        }
        guard let operation, let id = operationID else { return }
        let client = self.client
        authenticationURL = nil
        operation.cancel()
        let cleanup = Task {
            if let client { await client.shutdown() }
            _ = await operation.result
        }
        cancellation = (id, cleanup)
        await cleanup.value
        finishCancellation(id: id)
    }

    public func shutdown() async {
        isShutDown = true
        await cancel()
    }

    private func setAuthenticationURL(_ url: URL, for id: UUID) throws {
        guard operationID == id, cancellation == nil, !isShutDown else {
            throw CancellationError()
        }
        authenticationURL = url
    }

    private func clearAuthenticationURL(for id: UUID) {
        guard operationID == id else { return }
        authenticationURL = nil
    }

    private func finishCancellation(id: UUID) {
        guard cancellation?.id == id else { return }
        clearOperation(id: id)
        cancellation = nil
    }

    private func clearOperation(id: UUID) {
        guard operationID == id else { return }
        operationID = nil
        operation = nil
        client = nil
        authenticationURL = nil
    }
}
