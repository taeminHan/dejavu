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
        XCTAssertNotNil(state.claudeSnapshot)
        XCTAssertNil(state.claudeSnapshot?.fiveHour)
        XCTAssertNil(state.claudeSnapshot?.weekly)
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

    func testExpiredCarriedValuesDisappearWithoutFreshTimestamp() async {
        let old = Date(timeIntervalSince1970: 1000)
        let expired = UsageLimit(percent: 89, resetsAt: old)
        let previous = ApplicationState(
            claudeStatus: .ready,
            claudeSnapshot: .init(fiveHour: expired, weekly: expired, fable: expired, capturedAt: old),
            codexStatus: .ready,
            codexSnapshot: .init(weekly: expired, resetCredits: 3, resetCreditsExpireAt: old, planType: "plus"),
            updatedAt: old
        )
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: FailingProvider<ClaudeUsageSnapshot>(failure: .offline),
            codexProvider: FailingProvider<CodexUsageSnapshot>(failure: .offline),
            initialState: previous, now: { old.addingTimeInterval(1000) }
        )
        let result = await coordinator.refresh()
        XCTAssertNotNil(result.claudeSnapshot)
        XCTAssertNotNil(result.codexSnapshot)
        XCTAssertNil(result.claudeSnapshot?.fiveHour)
        XCTAssertNil(result.claudeSnapshot?.weekly)
        XCTAssertNil(result.claudeSnapshot?.fable)
        XCTAssertNil(result.codexSnapshot?.weekly)
        XCTAssertNil(result.codexSnapshot?.resetCredits)
        XCTAssertEqual(result.updatedAt, old)
    }

    func testWaitingForFirstDataIsNotLoginFailure() async {
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: FailingProvider<ClaudeUsageSnapshot>(failure: .waitingForData),
            codexProvider: FailingProvider<CodexUsageSnapshot>(failure: .unavailable)
        )
        let result = await coordinator.refresh()
        XCTAssertEqual(result.claudeStatus, .loading)
        XCTAssertNil(result.updatedAt)
    }

    func testClaudeOnlyWatchNeverReadsCodexOrAdvancesItsTimestamp() async {
        let checkedAt = Date(timeIntervalSince1970: 1000)
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 70),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: ImmediateProvider(snapshot: Self.claudeSnapshot(percent: 20)), codexProvider: codex,
            initialState: .init(claudeStatus: .ready, codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70), updatedAt: checkedAt),
            now: { checkedAt.addingTimeInterval(100) }
        )
        let result = await coordinator.refresh(includeCodex: false)
        let calls = await codex.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(result.codexSnapshot?.weekly?.percent, 71)
        XCTAssertEqual(result.updatedAt, checkedAt)
    }

    func testSuccessfulClaudeRefreshCannotRenewCarriedCodexTTL() async {
        let clock = TestClock(Date(timeIntervalSince1970: 1700))
        let claude = ClaudeUsageSnapshot(fiveHour: nil,
            weekly: UsageLimit(percent: 25, resetsAt: Date(timeIntervalSince1970: 5000)),
            capturedAt: Date(timeIntervalSince1970: 1700))
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: ImmediateProvider(snapshot: claude),
            codexProvider: FailingProvider<CodexUsageSnapshot>(failure: .offline),
            initialState: .init(claudeStatus: .ready, codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70),
                                updatedAt: Date(timeIntervalSince1970: 1000)),
            now: { clock.read() }
        )
        let first = await coordinator.refresh()
        XCTAssertEqual(first.codexSnapshot?.weekly?.percent, 71)
        clock.set(Date(timeIntervalSince1970: 2000))
        let second = await coordinator.refresh()
        XCTAssertNil(second.codexSnapshot?.weekly)
        XCTAssertEqual(second.claudeSnapshot?.weekly?.percent, 25)
    }

    func testClaudeIdentityResetPreservesSettledCodexWithoutReadingIt() async {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let previousCodex = Self.codexSnapshot(percent: 70)
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 10),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let initial = ApplicationState(
            claudeStatus: .rateLimited,
            claudeMessage: "Previous Claude identity",
            claudeSnapshot: Self.claudeSnapshot(percent: 60),
            codexStatus: .error,
            codexMessage: "Settled Codex failure",
            codexSnapshot: previousCodex,
            updatedAt: checkedAt,
            retryAt: checkedAt.addingTimeInterval(300),
            claudeIssue: .serverError,
            codexIssue: .responseChanged
        )
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: ImmediateProvider(snapshot: Self.claudeSnapshot(percent: 20)),
            codexProvider: codex,
            initialState: initial,
            now: { checkedAt.addingTimeInterval(100) }
        )

        let cleared = await coordinator.resetClaudeState()
        let codexCalls = await codex.callCount

        XCTAssertEqual(cleared.combinedStatus, .loading)
        XCTAssertEqual(cleared.claudeStatus, .loading)
        XCTAssertEqual(cleared.claudeMessage, ApplicationState.initial.claudeMessage)
        XCTAssertNil(cleared.claudeSnapshot)
        XCTAssertNil(cleared.claudeIssue)
        XCTAssertNil(cleared.retryAt)
        XCTAssertEqual(cleared.codexStatus, initial.codexStatus)
        XCTAssertEqual(cleared.codexMessage, initial.codexMessage)
        XCTAssertEqual(cleared.codexSnapshot, previousCodex)
        XCTAssertEqual(cleared.codexIssue, initial.codexIssue)
        XCTAssertEqual(cleared.updatedAt, checkedAt)
        XCTAssertEqual(codexCalls, 0)
    }

    func testClaudeIdentityResetCannotCarryPreviousValuesWhenNewIdentityReadFails() async {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(checkedAt.addingTimeInterval(700))
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 10),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: FailingProvider<ClaudeUsageSnapshot>(failure: .offline),
            codexProvider: codex,
            initialState: .init(claudeStatus: .ready,
                                claudeSnapshot: Self.claudeSnapshot(percent: 60),
                                codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70),
                                updatedAt: checkedAt),
            now: { clock.read() }
        )

        _ = await coordinator.resetClaudeState()
        let failure = await coordinator.refresh(includeCodex: false)
        XCTAssertEqual(failure.claudeStatus, .offline)
        XCTAssertNil(failure.claudeSnapshot)
        XCTAssertEqual(failure.codexSnapshot?.weekly?.percent, 71)
        XCTAssertEqual(failure.updatedAt, checkedAt)

        clock.set(checkedAt.addingTimeInterval(1_000))
        let laterFailure = await coordinator.refresh(includeCodex: false)
        let codexCalls = await codex.callCount
        XCTAssertNil(laterFailure.claudeSnapshot)
        XCTAssertNil(laterFailure.codexSnapshot?.weekly)
        XCTAssertEqual(laterFailure.updatedAt, checkedAt)
        XCTAssertEqual(codexCalls, 0)
    }

    func testClaudeIdentityResetInvalidatesAnOldInFlightCompletionBeforeItDrains() async {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let claude = GatedProvider(firstSnapshot: Self.claudeSnapshot(percent: 85),
                                  laterSnapshot: Self.claudeSnapshot(percent: 20))
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 10),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: claude,
            codexProvider: codex,
            initialState: .init(claudeStatus: .ready,
                                claudeSnapshot: Self.claudeSnapshot(percent: 60),
                                codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70),
                                updatedAt: checkedAt),
            now: { checkedAt.addingTimeInterval(100) }
        )

        let oldRefresh = Task { await coordinator.refresh(includeCodex: false) }
        await claude.waitUntilStarted()
        let reset = Task { await coordinator.resetClaudeState() }
        await claude.waitUntilCancelled()

        let whileDraining = await coordinator.currentState
        let ignoredRefresh = await coordinator.refresh(force: true, includeCodex: false)
        let callsWhileDraining = await claude.callCount
        XCTAssertNil(whileDraining.claudeSnapshot)
        XCTAssertEqual(whileDraining.claudeStatus, .loading)
        XCTAssertEqual(ignoredRefresh, whileDraining)
        XCTAssertEqual(callsWhileDraining, 1)

        // This fake intentionally returns an old value even after cancellation.
        await claude.releaseFirstRead()
        let cleared = await reset.value
        let oldCompletion = await oldRefresh.value
        XCTAssertNil(cleared.claudeSnapshot)
        XCTAssertNil(oldCompletion.claudeSnapshot)
        XCTAssertEqual(oldCompletion.codexSnapshot?.weekly?.percent, 71)

        let newIdentity = await coordinator.refresh(includeCodex: false)
        let codexCalls = await codex.callCount
        let isStopped = await coordinator.isStopped
        XCTAssertEqual(newIdentity.claudeSnapshot?.fiveHour?.percent, 20)
        XCTAssertEqual(codexCalls, 0)
        XCTAssertFalse(isStopped)
    }

    func testClaudeIdentityResetDoesNotResurrectAStoppedCoordinator() async {
        let claude = CountingProvider(snapshot: Self.claudeSnapshot(percent: 20),
                                      firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 70),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let initial = ApplicationState(claudeStatus: .loginRequired, codexStatus: .ready,
                                       codexSnapshot: Self.codexSnapshot(percent: 70))
        let coordinator = UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex,
                                                   initialState: initial)
        await coordinator.cancelAndWait()

        let reset = await coordinator.resetClaudeState()
        let laterRefresh = await coordinator.refresh(force: true)
        let isStopped = await coordinator.isStopped
        let claudeCalls = await claude.callCount
        let codexCalls = await codex.callCount
        XCTAssertEqual(reset, initial)
        XCTAssertEqual(laterRefresh, initial)
        XCTAssertTrue(isStopped)
        XCTAssertEqual(claudeCalls, 0)
        XCTAssertEqual(codexCalls, 0)
    }

    func testClaudeIdentityResetInvalidatesAForcedRefreshAlreadyWaitingForTheOldRead() async {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let claude = GatedProvider(firstSnapshot: Self.claudeSnapshot(percent: 85),
                                  laterSnapshot: Self.claudeSnapshot(percent: 20))
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: claude,
            codexProvider: ImmediateProvider(snapshot: Self.codexSnapshot(percent: 70)),
            initialState: .init(claudeStatus: .ready,
                                claudeSnapshot: Self.claudeSnapshot(percent: 60),
                                codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70),
                                updatedAt: checkedAt),
            now: { checkedAt }
        )

        let oldRefresh = Task { await coordinator.refresh(includeCodex: false) }
        await claude.waitUntilStarted()
        let queuedForcedRefresh = Task { await coordinator.refresh(force: true, includeCodex: false) }
        await claude.waitUntilCancelled()
        let reset = Task { await coordinator.resetClaudeState() }
        await waitUntilClaudeCleared(coordinator)
        await claude.releaseFirstRead()

        _ = await reset.value
        let forcedCompletion = await queuedForcedRefresh.value
        let oldCompletion = await oldRefresh.value
        let claudeCalls = await claude.callCount
        XCTAssertNil(forcedCompletion.claudeSnapshot)
        XCTAssertNil(oldCompletion.claudeSnapshot)
        XCTAssertEqual(claudeCalls, 1)
    }

    func testShutdownDuringClaudeIdentityResetKeepsTheResetDrainedAndStopped() async {
        let claude = GatedProvider(firstSnapshot: Self.claudeSnapshot(percent: 85),
                                  laterSnapshot: Self.claudeSnapshot(percent: 20))
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: claude,
            codexProvider: ImmediateProvider(snapshot: Self.codexSnapshot(percent: 70))
        )
        let oldRefresh = Task { await coordinator.refresh(includeCodex: false) }
        await claude.waitUntilStarted()
        let reset = Task { await coordinator.resetClaudeState() }
        await claude.waitUntilCancelled()
        let shutdown = Task { await coordinator.cancelAndWait() }
        await waitUntilStopped(coordinator)
        await claude.releaseFirstRead()

        _ = await reset.value
        _ = await oldRefresh.value
        await shutdown.value
        let laterRefresh = await coordinator.refresh(force: true)
        let claudeCalls = await claude.callCount
        XCTAssertNil(laterRefresh.claudeSnapshot)
        XCTAssertEqual(claudeCalls, 1)
    }

    func testConcurrentClaudeIdentityResetsDrainTheOldReadBeforeLatestCallerRefreshes() async {
        let checkedAt = Date(timeIntervalSince1970: 1_000)
        let claude = GatedProvider(firstSnapshot: Self.claudeSnapshot(percent: 85),
                                  laterSnapshot: Self.claudeSnapshot(percent: 20))
        let codex = CountingProvider(snapshot: Self.codexSnapshot(percent: 10),
                                     firstDelayNanoseconds: 0, laterDelayNanoseconds: 0)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: claude,
            codexProvider: codex,
            initialState: .init(claudeStatus: .ready,
                                claudeSnapshot: Self.claudeSnapshot(percent: 60),
                                codexStatus: .ready,
                                codexSnapshot: Self.codexSnapshot(percent: 70),
                                updatedAt: checkedAt),
            now: { checkedAt }
        )
        let oldRefresh = Task { await coordinator.refresh(includeCodex: false) }
        await claude.waitUntilStarted()
        let firstReset = Task { await coordinator.resetClaudeState() }
        await claude.waitUntilCancelled()
        let latestCaller = Task {
            let cleared = await coordinator.resetClaudeState()
            let refreshed = await coordinator.refresh(includeCodex: false)
            return (cleared, refreshed)
        }
        // Leave the first read held while the second caller joins its drain.
        // Actor hops yield execution without wall-clock sleeps or real I/O.
        for _ in 0..<100 { _ = await coordinator.currentState }
        let callsBeforeRelease = await claude.callCount
        XCTAssertEqual(callsBeforeRelease, 1)
        await claude.releaseFirstRead()

        _ = await firstReset.value
        _ = await oldRefresh.value
        let (cleared, refreshed) = await latestCaller.value
        let settled = await coordinator.currentState
        let claudeCalls = await claude.callCount
        let codexCalls = await codex.callCount
        XCTAssertNil(cleared.claudeSnapshot)
        XCTAssertEqual(refreshed.claudeSnapshot?.fiveHour?.percent, 20)
        XCTAssertEqual(settled.claudeSnapshot?.fiveHour?.percent, 20)
        XCTAssertEqual(refreshed.codexSnapshot?.weekly?.percent, 71)
        XCTAssertEqual(refreshed.updatedAt, checkedAt)
        XCTAssertEqual(claudeCalls, 2)
        XCTAssertEqual(codexCalls, 0)
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

    private func waitUntilClaudeCleared(_ coordinator: UsageRefreshCoordinator) async {
        for _ in 0..<2_000 {
            let state = await coordinator.currentState
            if state.claudeStatus == .loading, state.claudeSnapshot == nil { return }
            await Task.yield()
        }
        XCTFail("Claude identity reset did not clear the old snapshot")
    }

    private func waitUntilStopped(_ coordinator: UsageRefreshCoordinator) async {
        for _ in 0..<2_000 {
            if await coordinator.isStopped { return }
            await Task.yield()
        }
        XCTFail("Coordinator did not enter shutdown while draining the old read")
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

/// A synthetic reader that reports cancellation but deliberately waits for an
/// explicit release. No timers, real credentials or provider requests are used.
private actor GatedProvider<Snapshot: Sendable>: UsageProviding {
    private let firstSnapshot: Snapshot
    private let laterSnapshot: Snapshot
    private var pendingRead: CheckedContinuation<Snapshot, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelled = false
    private(set) var callCount = 0

    init(firstSnapshot: Snapshot, laterSnapshot: Snapshot) {
        self.firstSnapshot = firstSnapshot
        self.laterSnapshot = laterSnapshot
    }

    func fetchUsage() async throws -> Snapshot {
        callCount += 1
        guard callCount == 1 else { return laterSnapshot }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingRead = continuation
                startWaiters.forEach { $0.resume() }
                startWaiters.removeAll()
            }
        } onCancel: {
            Task { await self.recordCancellation() }
        }
    }

    func waitUntilStarted() async {
        guard pendingRead == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilCancelled() async {
        guard !cancelled else { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func releaseFirstRead() {
        pendingRead?.resume(returning: firstSnapshot)
        pendingRead = nil
    }

    private func recordCancellation() {
        cancelled = true
        cancellationWaiters.forEach { $0.resume() }
        cancellationWaiters.removeAll()
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

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Date) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
