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
    case waitingForData
    case tokenRefreshPending
    case serverFailed
    case responseChanged
    case permissionDenied
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
        let issue: UsageIssue?

        init(status: UsageStatus, snapshot: Snapshot?, message: String, retryAt: Date?, issue: UsageIssue? = nil) {
            self.status = status
            self.snapshot = snapshot
            self.message = message
            self.retryAt = retryAt
            self.issue = issue
        }
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
        let includesCodex: Bool
    }

    private let claudeProvider: AnyUsageProvider<ClaudeUsageSnapshot>
    private let codexProvider: AnyUsageProvider<CodexUsageSnapshot>
    private let now: @Sendable () -> Date
    private var state: ApplicationState
    private var inFlight: InFlight?
    private var nextIdentifier: UInt64 = 0
    private var stopped = false
    private var codexCapturedAt: Date?
    private var claudeResetGeneration: UInt64 = 0
    private var isResettingClaude = false
    private var claudeResetTask: Task<RefreshTaskResult, Never>?

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
        codexCapturedAt = initialState.updatedAt
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
        codexCapturedAt = initialState.updatedAt
    }

    public var currentState: ApplicationState { state }
    public var isStopped: Bool { stopped }

    public func refresh(trigger: RefreshTrigger) async -> ApplicationState {
        await refresh(force: trigger == .forced)
    }

    public func refresh(force: Bool = false, includeCodex: Bool = true) async -> ApplicationState {
        guard !stopped, !isResettingClaude else { return state }
        let requestedGeneration = claudeResetGeneration

        if let current = inFlight {
            if !force {
                return await finish(current)
            }

            current.task.cancel()
            _ = await current.task.value
            guard !stopped, !isResettingClaude,
                  requestedGeneration == claudeResetGeneration else { return state }

            if let newer = inFlight, newer.identifier != current.identifier {
                return await finish(newer)
            }
            if inFlight?.identifier == current.identifier {
                inFlight = nil
            }
        }

        return await startRefresh(includeCodex: includeCodex)
    }

    public func cancelAndWait() async {
        stopped = true
        let current = inFlight
        guard let task = current?.task ?? claudeResetTask else { return }
        task.cancel()
        _ = await task.value
        if let current, inFlight?.identifier == current.identifier {
            inFlight = nil
        }
    }

    /// Cancels the current provider read without permanently stopping future
    /// refreshes. This is used before resetting Dejavu-owned local data.
    public func cancelActiveRefresh() async {
        guard !stopped else { return }
        let current = inFlight
        guard let task = current?.task ?? claudeResetTask else { return }
        task.cancel()
        _ = await task.value
        if let current, inFlight?.identifier == current.identifier {
            inFlight = nil
        }
    }

    public func resetState() async {
        guard !stopped else { return }
        await cancelActiveRefresh()
        state = .initial
        codexCapturedAt = nil
    }

    /// Clears values belonging to the previously selected Claude credential
    /// identity. Invalidate the old refresh before draining it so that neither
    /// its finish nor an already waiting forced refresh can restore old values.
    /// Codex remains the last independently settled reading, including its age.
    public func resetClaudeState() async -> ApplicationState {
        guard !stopped else { return state }
        if isResettingClaude {
            let resetGeneration = claudeResetGeneration
            if let task = claudeResetTask { _ = await task.value }
            completeClaudeReset(generation: resetGeneration)
            return state
        }

        claudeResetGeneration &+= 1
        let resetGeneration = claudeResetGeneration
        isResettingClaude = true
        let current = inFlight
        claudeResetTask = current?.task
        inFlight = nil
        current?.task.cancel()
        state = ApplicationState(
            combinedStatus: .loading,
            claudeStatus: .loading,
            claudeMessage: ApplicationState.initial.claudeMessage,
            codexStatus: state.codexStatus,
            codexMessage: state.codexMessage,
            codexSnapshot: state.codexSnapshot,
            updatedAt: state.updatedAt,
            codexIssue: state.codexIssue
        )

        if let current { _ = await current.task.value }
        completeClaudeReset(generation: resetGeneration)
        return state
    }

    private func completeClaudeReset(generation: UInt64) {
        if generation == claudeResetGeneration {
            claudeResetTask = nil
            isResettingClaude = false
        }
    }

    private func startRefresh(includeCodex: Bool) async -> ApplicationState {
        guard !stopped, !isResettingClaude else { return state }

        let previousState = state
        state = previousState.loading()
        nextIdentifier &+= 1

        let claudeProvider = self.claudeProvider
        let codexProvider = self.codexProvider
        let task = Task {
            await Self.performRefresh(
                claudeProvider: claudeProvider,
                codexProvider: codexProvider,
                previousState: previousState,
                includeCodex: includeCodex
            )
        }
        let current = InFlight(
            identifier: nextIdentifier,
            previousState: previousState,
            task: task,
            includesCodex: includeCodex
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
        let checkedAt = now()
        let codexSnapshot = snapshotAfterRefresh(
            result: payload.codex,
            previous: current.previousState.codexSnapshot
        )
        if current.includesCodex, payload.codex.snapshot != nil { codexCapturedAt = checkedAt }
        let freshness = UsageFreshnessPolicy()
        let freshClaude = claudeSnapshot.map { snapshot in
            ClaudeUsageSnapshot(
                fiveHour: freshness.freshLimit(snapshot.fiveHour, capturedAt: snapshot.capturedAt, now: checkedAt),
                weekly: freshness.freshLimit(snapshot.weekly, capturedAt: snapshot.capturedAt, now: checkedAt),
                fable: freshness.freshLimit(snapshot.fable, capturedAt: snapshot.capturedAt, now: checkedAt),
                source: snapshot.source,
                capturedAt: snapshot.capturedAt
            )
        }
        let capturedAt = codexCapturedAt ?? checkedAt
        let freshCodex = codexSnapshot.map { snapshot in
            CodexUsageSnapshot(
                weekly: freshness.freshLimit(snapshot.weekly, capturedAt: capturedAt, now: checkedAt),
                resetCredits: snapshot.resetCreditsExpireAt.map { $0 <= checkedAt } == true ? nil : snapshot.resetCredits,
                resetCreditsExpireAt: snapshot.resetCreditsExpireAt,
                planType: snapshot.planType
            )
        }
        let retryAt = [payload.claude.retryAt, payload.codex.retryAt]
            .compactMap { $0 }
            .min()

        state = ApplicationState(
            claudeStatus: payload.claude.status,
            claudeMessage: payload.claude.message,
            claudeSnapshot: freshClaude,
            codexStatus: payload.codex.status,
            codexMessage: payload.codex.message,
            codexSnapshot: freshCodex,
            updatedAt: !current.includesCodex && current.previousState.codexSnapshot != nil
                ? current.previousState.updatedAt
                : (payload.claude.snapshot != nil || (current.includesCodex && payload.codex.snapshot != nil)
                    ? checkedAt : current.previousState.updatedAt),
            retryAt: retryAt,
            claudeIssue: payload.claude.issue,
            codexIssue: payload.codex.issue
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
        codexProvider: AnyUsageProvider<CodexUsageSnapshot>,
        previousState: ApplicationState,
        includeCodex: Bool
    ) async -> RefreshTaskResult {
        do {
            async let claude = read(provider: claudeProvider, name: "Claude")
            async let codex = includeCodex ? read(provider: codexProvider, name: "Codex")
                : ProviderResult(status: previousState.codexStatus, snapshot: previousState.codexSnapshot,
                                 message: previousState.codexMessage, retryAt: nil, issue: previousState.codexIssue)
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
            var issue: UsageIssue? = nil
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
            case .waitingForData:
                status = .loading
                message = "\(name) is waiting for usage data"
                retryAt = nil
                issue = .waitingForData
            case .tokenRefreshPending:
                status = .error
                message = "\(name) token refresh is pending; open Claude Code"
                retryAt = nil
                issue = .tokenRefreshPending
            case .serverFailed:
                status = .error
                message = "\(name) server is unavailable; retrying automatically"
                retryAt = nil
                issue = .serverError
            case .responseChanged:
                status = .error
                message = "\(name) usage response changed; check for an app update"
                retryAt = nil
                issue = .responseChanged
            case .permissionDenied:
                status = .unavailable
                message = "\(name) credential access was denied; review macOS permissions"
                retryAt = nil
                issue = .permissionDenied
            }
            return ProviderResult(status: status, snapshot: nil, message: message, retryAt: retryAt, issue: issue)
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
