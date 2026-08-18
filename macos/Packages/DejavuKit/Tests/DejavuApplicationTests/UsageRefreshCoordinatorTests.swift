import XCTest
import DejavuDomain
@testable import DejavuApplication

final class UsageRefreshCoordinatorTests: XCTestCase {
    func testScheduledRefreshesCoalesceOntoOneProviderRead() async {
        let claude = CountingProvider(
            snapshot: Self.claudeSnapshot(percent: 12),
            firstDelayNanoseconds: 80_000_000,
            laterDelayNanoseconds: 80_000_000
        )
        let codex = CountingProvider(
            snapshot: Self.codexSnapshot(percent: 34),
            firstDelayNanoseconds: 80_000_000,
            laterDelayNanoseconds: 80_000_000
        )
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)

        async let first = coordinator.refresh()
        async let second = coordinator.refresh()
        let (firstState, secondState) = await (first, second)
        let claudeCallCount = await claude.callCount
        let codexCallCount = await codex.callCount

        XCTAssertEqual(firstState, secondState)
        XCTAssertEqual(firstState.combinedStatus, .ready)
        XCTAssertEqual(claudeCallCount, 1)
        XCTAssertEqual(codexCallCount, 1)
    }

    func testForcedRefreshCancelsThenWaitsForActiveReadsBeforeStartingNewOnes() async throws {
        let claude = CountingProvider(
            snapshot: Self.claudeSnapshot(percent: 25),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let codex = CountingProvider(
            snapshot: Self.codexSnapshot(percent: 50),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)

        let original = Task { await coordinator.refresh() }
        try await waitUntilStarted(claude: claude, codex: codex)
        let forcedState = await coordinator.refresh(force: true)
        _ = await original.value
        let claudeCallCount = await claude.callCount
        let codexCallCount = await codex.callCount
        let claudeCancellationCount = await claude.cancellationCount
        let codexCancellationCount = await codex.cancellationCount

        XCTAssertEqual(forcedState.combinedStatus, .ready)
        XCTAssertEqual(claudeCallCount, 2)
        XCTAssertEqual(codexCallCount, 2)
        XCTAssertEqual(claudeCancellationCount, 1)
        XCTAssertEqual(codexCancellationCount, 1)
    }

    func testProviderReadsBeginInParallel() async throws {
        let claude = CountingProvider(
            snapshot: Self.claudeSnapshot(percent: 10),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let codex = CountingProvider(
            snapshot: Self.codexSnapshot(percent: 10),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)

        let refresh = Task { await coordinator.refresh() }
        try await waitUntilStarted(claude: claude, codex: codex)
        let claudeCallCount = await claude.callCount
        let codexCallCount = await codex.callCount

        XCTAssertEqual(claudeCallCount, 1)
        XCTAssertEqual(codexCallCount, 1)

        await coordinator.cancelAndWait()
        _ = await refresh.value
    }

    func testCancelActiveRefreshAllowsALaterRefresh() async throws {
        let claude = CountingProvider(
            snapshot: Self.claudeSnapshot(percent: 10),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let codex = CountingProvider(
            snapshot: Self.codexSnapshot(percent: 20),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)

        let first = Task { await coordinator.refresh() }
        try await waitUntilStarted(claude: claude, codex: codex)
        await coordinator.cancelActiveRefresh()
        _ = await first.value
        let next = await coordinator.refresh()
        let isStopped = await coordinator.isStopped
        let claudeCallCount = await claude.callCount
        let codexCallCount = await codex.callCount
        let claudeCancellationCount = await claude.cancellationCount
        let codexCancellationCount = await codex.cancellationCount

        XCTAssertEqual(next.combinedStatus, .ready)
        XCTAssertFalse(isStopped)
        XCTAssertEqual(claudeCallCount, 2)
        XCTAssertEqual(codexCallCount, 2)
        XCTAssertEqual(claudeCancellationCount, 1)
        XCTAssertEqual(codexCancellationCount, 1)
    }

    func testIndependentFailurePreservesOnlyTheFailedProvidersPreviousSnapshot() async {
        let previousClaude = Self.claudeSnapshot(percent: 60)
        let previousCodex = Self.codexSnapshot(percent: 70)
        let initial = ApplicationState(
            claudeStatus: .ready,
            claudeSnapshot: previousClaude,
            codexStatus: .ready,
            codexSnapshot: previousCodex,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let claude = FailingProvider<ClaudeUsageSnapshot>(failure: .offline)
        let newCodex = Self.codexSnapshot(percent: 15)
        let codex = ImmediateProvider(snapshot: newCodex)
        let completionDate = Date(timeIntervalSince1970: 2_000)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: claude,
            codexProvider: codex,
            initialState: initial,
            now: { completionDate }
        )

        let state = await coordinator.refresh()

        XCTAssertEqual(state.combinedStatus, .ready)
        XCTAssertEqual(state.claudeStatus, .offline)
        XCTAssertEqual(state.claudeSnapshot, previousClaude)
        XCTAssertEqual(state.codexStatus, .ready)
        XCTAssertEqual(state.codexSnapshot, newCodex)
        XCTAssertEqual(state.updatedAt, completionDate)
    }

    func testLoginRequiredClearsAnObsoletePreviousSnapshot() async {
        let initial = ApplicationState(
            claudeStatus: .ready,
            claudeSnapshot: Self.claudeSnapshot(percent: 60),
            codexStatus: .ready,
            codexSnapshot: Self.codexSnapshot(percent: 70)
        )
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: FailingProvider<ClaudeUsageSnapshot>(failure: .loginRequired),
            codexProvider: ImmediateProvider(snapshot: Self.codexSnapshot(percent: 20)),
            initialState: initial
        )

        let state = await coordinator.refresh()

        XCTAssertEqual(state.claudeStatus, .loginRequired)
        XCTAssertNil(state.claudeSnapshot)
        XCTAssertNotNil(state.codexSnapshot)
    }

    func testUnknownProviderErrorIsClassifiedWithoutLeakingItsDescription() async {
        let secret = "Bearer highly-sensitive-value"
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: ArbitraryFailingProvider<ClaudeUsageSnapshot>(error: SecretError(secret: secret)),
            codexProvider: FailingProvider<CodexUsageSnapshot>(failure: .unavailable)
        )

        let state = await coordinator.refresh()

        XCTAssertEqual(state.claudeStatus, .error)
        XCTAssertFalse(state.claudeMessage.contains(secret))
        XCTAssertFalse(state.claudeMessage.localizedCaseInsensitiveContains("bearer"))
    }

    func testEarliestProviderRetryDateBecomesApplicationRetryDate() async {
        let early = Date(timeIntervalSince1970: 2_000)
        let late = Date(timeIntervalSince1970: 3_000)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: FailingProvider<ClaudeUsageSnapshot>(failure: .rateLimited(retryAt: late)),
            codexProvider: FailingProvider<CodexUsageSnapshot>(failure: .rateLimited(retryAt: early))
        )

        let state = await coordinator.refresh()

        XCTAssertEqual(state.combinedStatus, .rateLimited)
        XCTAssertEqual(state.retryAt, early)
    }

    func testShutdownCancelsOwnedWorkAndRejectsLaterRefreshes() async throws {
        let claude = CountingProvider(
            snapshot: Self.claudeSnapshot(percent: 10),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let codex = CountingProvider(
            snapshot: Self.codexSnapshot(percent: 20),
            firstDelayNanoseconds: 5_000_000_000,
            laterDelayNanoseconds: 0
        )
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)

        let refresh = Task { await coordinator.refresh() }
        try await waitUntilStarted(claude: claude, codex: codex)
        await coordinator.cancelAndWait()
        let stateAfterShutdown = await coordinator.refresh(force: true)
        _ = await refresh.value
        let isStopped = await coordinator.isStopped
        let claudeCallCount = await claude.callCount
        let codexCallCount = await codex.callCount
        let claudeCancellationCount = await claude.cancellationCount
        let codexCancellationCount = await codex.cancellationCount

        XCTAssertTrue(isStopped)
        XCTAssertEqual(claudeCallCount, 1)
        XCTAssertEqual(codexCallCount, 1)
        XCTAssertEqual(claudeCancellationCount, 1)
        XCTAssertEqual(codexCancellationCount, 1)
        XCTAssertEqual(stateAfterShutdown.combinedStatus, .loading)
    }

    private func waitUntilStarted(
        claude: CountingProvider<ClaudeUsageSnapshot>,
        codex: CountingProvider<CodexUsageSnapshot>
    ) async throws {
        for _ in 0..<200 {
            if await claude.callCount == 1, await codex.callCount == 1 { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Both providers did not start")
    }

    private static func claudeSnapshot(percent: Double) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: percent),
            weekly: UsageLimit(percent: percent + 1),
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    private static func codexSnapshot(percent: Double) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            weekly: UsageLimit(percent: percent + 1),
            resetCredits: 2,
            resetCreditsExpireAt: nil,
            planType: "plus"
        )
    }
}

private actor CountingProvider<Snapshot: Sendable>: UsageProviding {
    private let snapshot: Snapshot
    private let firstDelayNanoseconds: UInt64
    private let laterDelayNanoseconds: UInt64
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    init(
        snapshot: Snapshot,
        firstDelayNanoseconds: UInt64,
        laterDelayNanoseconds: UInt64
    ) {
        self.snapshot = snapshot
        self.firstDelayNanoseconds = firstDelayNanoseconds
        self.laterDelayNanoseconds = laterDelayNanoseconds
    }

    func fetchUsage() async throws -> Snapshot {
        callCount += 1
        let delay = callCount == 1 ? firstDelayNanoseconds : laterDelayNanoseconds
        do {
            try await Task.sleep(nanoseconds: delay)
        } catch {
            cancellationCount += 1
            throw error
        }
        return snapshot
    }
}

private struct ImmediateProvider<Snapshot: Sendable>: UsageProviding {
    let snapshot: Snapshot

    func fetchUsage() async throws -> Snapshot { snapshot }
}

private struct FailingProvider<Snapshot: Sendable>: UsageProviding {
    let failure: UsageProviderFailure

    func fetchUsage() async throws -> Snapshot { throw failure }
}

private struct ArbitraryFailingProvider<Snapshot: Sendable>: UsageProviding {
    let error: SecretError

    func fetchUsage() async throws -> Snapshot { throw error }
}

private struct SecretError: Error, Sendable {
    let secret: String
}
