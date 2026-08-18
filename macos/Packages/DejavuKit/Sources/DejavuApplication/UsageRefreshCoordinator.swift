import Foundation
import DejavuDomain

public protocol UsageProviding: Sendable {
    associatedtype Snapshot: Sendable

    func fetchUsage() async throws -> Snapshot
}

public struct AnyUsageProvider<Snapshot: Sendable>: Sendable {
    private let fetchOperation: @Sendable () async throws -> Snapshot

    public init<Provider: UsageProviding>(_ provider: Provider) where Provider.Snapshot == Snapshot {
        fetchOperation = { try await provider.fetchUsage() }
    }

    public init(fetch: @escaping @Sendable () async throws -> Snapshot) {
        fetchOperation = fetch
    }

    public func fetchUsage() async throws -> Snapshot {
        try await fetchOperation()
    }
}

public enum UsageProviderFailure: Error, Hashable, Sendable {
    case loginRequired
    case rateLimited(retryAt: Date?)
    case offline
    case unavailable
    case failed
}

public enum RefreshTrigger: Sendable {
    case scheduled
    case forced
}

public actor UsageRefreshCoordinator {
    private struct ProviderResult<Snapshot: Sendable>: Sendable {
        let status: UsageStatus
        let snapshot: Snapshot?
        let message: String
        let retryAt: Date?
    }

    private struct RefreshPayload: Sendable {
        let claude: ProviderResult<ClaudeUsageSnapshot>
        let codex: ProviderResult<CodexUsageSnapshot>
    }

    private enum RefreshTaskResult: Sendable {
        case completed(RefreshPayload)
        case cancelled
    }

    private struct InFlight: Sendable {
        let identifier: UInt64
        let previousState: ApplicationState
        let task: Task<RefreshTaskResult, Never>
    }

    private let claudeProvider: AnyUsageProvider<ClaudeUsageSnapshot>
    private let codexProvider: AnyUsageProvider<CodexUsageSnapshot>
    private let now: @Sendable () -> Date
    private var state: ApplicationState
    private var inFlight: InFlight?
    private var nextIdentifier: UInt64 = 0
    private var stopped = false

    public init<ClaudeProvider: UsageProviding, CodexProvider: UsageProviding>(
        claudeProvider: ClaudeProvider,
        codexProvider: CodexProvider,
        initialState: ApplicationState = .initial,
        now: @escaping @Sendable () -> Date = { Date() }
    ) where ClaudeProvider.Snapshot == ClaudeUsageSnapshot, CodexProvider.Snapshot == CodexUsageSnapshot {
        self.claudeProvider = AnyUsageProvider(claudeProvider)
        self.codexProvider = AnyUsageProvider(codexProvider)
        self.state = initialState
        self.now = now
    }

    public init(
        claudeProvider: AnyUsageProvider<ClaudeUsageSnapshot>,
        codexProvider: AnyUsageProvider<CodexUsageSnapshot>,
        initialState: ApplicationState = .initial,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.claudeProvider = claudeProvider
        self.codexProvider = codexProvider
        self.state = initialState
        self.now = now
    }

    public var currentState: ApplicationState { state }
    public var isStopped: Bool { stopped }

    public func refresh(trigger: RefreshTrigger) async -> ApplicationState {
        await refresh(force: trigger == .forced)
    }

    public func refresh(force: Bool = false) async -> ApplicationState {
        guard !stopped else { return state }

        if let current = inFlight {
            if !force {
                return await finish(current)
            }

            current.task.cancel()
            _ = await current.task.value
            guard !stopped else { return state }

            if let newer = inFlight, newer.identifier != current.identifier {
                return await finish(newer)
            }
            if inFlight?.identifier == current.identifier {
                inFlight = nil
            }
        }

        return await startRefresh()
    }

    public func cancelAndWait() async {
        stopped = true
        guard let current = inFlight else { return }
        current.task.cancel()
        _ = await current.task.value
        if inFlight?.identifier == current.identifier {
            inFlight = nil
        }
    }

    /// Cancels the current provider read without permanently stopping future
    /// refreshes. This is used before resetting Dejavu-owned local data.
    public func cancelActiveRefresh() async {
        guard !stopped, let current = inFlight else { return }
        current.task.cancel()
        _ = await current.task.value
        if inFlight?.identifier == current.identifier {
            inFlight = nil
        }
    }

    public func resetState() async {
        guard !stopped else { return }
        await cancelActiveRefresh()
        state = .initial
    }

    private func startRefresh() async -> ApplicationState {
        guard !stopped else { return state }

        let previousState = state
        state = previousState.loading()
        nextIdentifier &+= 1

        let claudeProvider = self.claudeProvider
        let codexProvider = self.codexProvider
        let task = Task {
            await Self.performRefresh(
                claudeProvider: claudeProvider,
                codexProvider: codexProvider
            )
        }
        let current = InFlight(
            identifier: nextIdentifier,
            previousState: previousState,
            task: task
        )
        inFlight = current
        return await finish(current)
    }

    private func finish(_ current: InFlight) async -> ApplicationState {
        let result = await current.task.value
        guard !stopped, inFlight?.identifier == current.identifier else { return state }
        inFlight = nil

        guard case let .completed(payload) = result else {
            return state
        }

        let claudeSnapshot = snapshotAfterRefresh(
            result: payload.claude,
            previous: current.previousState.claudeSnapshot
        )
        let codexSnapshot = snapshotAfterRefresh(
            result: payload.codex,
            previous: current.previousState.codexSnapshot
        )
        let retryAt = [payload.claude.retryAt, payload.codex.retryAt]
            .compactMap { $0 }
            .min()

        state = ApplicationState(
            claudeStatus: payload.claude.status,
            claudeMessage: payload.claude.message,
            claudeSnapshot: claudeSnapshot,
            codexStatus: payload.codex.status,
            codexMessage: payload.codex.message,
            codexSnapshot: codexSnapshot,
            updatedAt: now(),
            retryAt: retryAt
        )
        return state
    }

    private func snapshotAfterRefresh<Snapshot: Sendable>(
        result: ProviderResult<Snapshot>,
        previous: Snapshot?
    ) -> Snapshot? {
        if let snapshot = result.snapshot { return snapshot }
        switch result.status {
        case .loading, .rateLimited, .offline, .error:
            return previous
        case .ready, .loginRequired, .unavailable:
            return nil
        }
    }

    private static func performRefresh(
        claudeProvider: AnyUsageProvider<ClaudeUsageSnapshot>,
        codexProvider: AnyUsageProvider<CodexUsageSnapshot>
    ) async -> RefreshTaskResult {
        do {
            async let claude = read(provider: claudeProvider, name: "Claude")
            async let codex = read(provider: codexProvider, name: "Codex")
            let payload = try await RefreshPayload(claude: claude, codex: codex)
            try Task.checkCancellation()
            return .completed(payload)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .cancelled
        }
    }

    private static func read<Snapshot: Sendable>(
        provider: AnyUsageProvider<Snapshot>,
        name: String
    ) async throws -> ProviderResult<Snapshot> {
        do {
            let snapshot = try await provider.fetchUsage()
            try Task.checkCancellation()
            return ProviderResult(
                status: .ready,
                snapshot: snapshot,
                message: "\(name) usage is current",
                retryAt: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as UsageProviderFailure {
            let status: UsageStatus
            let message: String
            let retryAt: Date?
            switch failure {
            case .loginRequired:
                status = .loginRequired
                message = "\(name) sign-in is required"
                retryAt = nil
            case let .rateLimited(date):
                status = .rateLimited
                message = "\(name) is temporarily rate limited"
                retryAt = date
            case .offline:
                status = .offline
                message = "\(name) is offline"
                retryAt = nil
            case .unavailable:
                status = .unavailable
                message = "\(name) is unavailable"
                retryAt = nil
            case .failed:
                status = .error
                message = "\(name) usage could not be read"
                retryAt = nil
            }
            return ProviderResult(status: status, snapshot: nil, message: message, retryAt: retryAt)
        } catch {
            try Task.checkCancellation()
            return ProviderResult(
                status: .error,
                snapshot: nil,
                message: "\(name) usage could not be read",
                retryAt: nil
            )
        }
    }
}
