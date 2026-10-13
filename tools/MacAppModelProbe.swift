import AppKit
import Foundation
import DejavuApplication
import DejavuDomain
import DejavuPersistence
import DejavuProviders

/// Compiled together with the actual AppModel.swift, not a copied model.
/// Only temporary Dejavu data and injected synthetic providers are used.
@main
@MainActor
struct MacAppModelProbe {
    private static var checked = 0

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-app-model-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try await firstRunAndAutomaticDiagnostics(in: directory.appendingPathComponent("first-run/dejavu"))
        try await resetRevokesConsent(in: directory.appendingPathComponent("reset/dejavu"))
        try await resetFailureStillRevokesConsent(in: directory.appendingPathComponent("reset-failure/dejavu"))
        try await resetRejectsReentrantConsent(in: directory.appendingPathComponent("reset-reentrant/dejavu"))
        try await shutdownPersistsLatestPreferences(in: directory.appendingPathComponent("shutdown/dejavu"))
        try await shutdownBeforeLoadPreservesUnchangedSettings(in: directory.appendingPathComponent("early-shutdown/dejavu"))
        try await identitySelectionClearsOldValuesAndPersists(in: directory.appendingPathComponent("identity/dejavu"))
        try await latestIdentityWinsDuringActiveRead(in: directory.appendingPathComponent("identity-race/dejavu"))
        print("Native AppModel regressions: \(checked) checked, 0 failed (synthetic providers; temporary settings only).")
    }

    private static func firstRunAndAutomaticDiagnostics(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        let model = AppModel(settingsStore: store, refreshCoordinator: coordinator(), unregisterLoginItem: {})
        model.widgetFrame = CGRect(x: 12, y: 20, width: 420, height: 60)
        model.start()
        try await wait { model.settingsAreLoaded && !model.isRefreshing && model.domainState.combinedStatus == .ready }
        try check(!model.firstRunCompleted, "A fresh installation must retain its first-run state.")

        let statusURL = directory.appendingPathComponent("status.json")
        try await wait { FileManager.default.fileExists(atPath: statusURL.path) }
        let data = try Data(contentsOf: statusURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let diagnostics = try decoder.decode(DiagnosticsSnapshot.self, from: data)
        try check(diagnostics.claude.fiveHourPercent == 32, "Automatic diagnostics must contain the latest synthetic Claude value.")
        try check(diagnostics.codex.weeklyPercent == 84, "Automatic diagnostics must contain the latest synthetic Codex value.")
        try check(diagnostics.codexResetCredits == 7, "Details-only credit count must remain available in diagnostics.")
        try check(diagnostics.widget?.width == 420 && diagnostics.widget?.height == 60, "Diagnostics must record actual widget dimensions.")
        try check(diagnostics.widget?.topLeftX == 12 && diagnostics.widget?.topLeftY == 80, "Diagnostics must record the actual top-left frame.")
        let text = String(decoding: data, as: UTF8.self).lowercased()
        for prohibited in ["authorization", "credential", "accountid", "prompt", "conversation", "synthetic-private-plan"] {
            try check(!text.contains(prohibited), "Diagnostics must not contain private fields or unapproved provider text.")
        }

        model.markOnboardingCompleted()
        try check(model.firstRunCompleted, "Completing onboarding must update the live model immediately.")
        try await wait { await store.load().firstRunCompleted }
        await model.shutdown()
        let restarted = AppModel(settingsStore: store, refreshCoordinator: coordinator(), unregisterLoginItem: {})
        restarted.start()
        try await wait { restarted.settingsAreLoaded }
        try check(restarted.firstRunCompleted, "Onboarding completion must survive an app-model restart.")
        await restarted.shutdown()
    }

    private static func resetRevokesConsent(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        var saved = AppSettings()
        saved.extendedFableAccessEnabled = true
        saved.claudeCredentialIdentity = .previousDejavuDefault
        saved.firstRunCompleted = true
        try await store.save(saved)
        let policy = ClaudeExtendedAccessPolicy(enabled: false)
        var unregistered = 0
        let model = AppModel(
            settingsStore: store,
            refreshCoordinator: coordinator(),
            extendedAccessPolicy: policy,
            unregisterLoginItem: { unregistered += 1 }
        )
        model.start()
        try await wait {
            let enabled = await policy.isEnabled()
            return model.settingsAreLoaded && !model.isRefreshing && enabled
        }
        try check(model.extendedFableAccessEnabled, "Saved consent must be loaded before testing reset.")
        let result = await model.resetLocalData()
        try check(result == .reset, "Reset must succeed with an injected login-item action.")
        try check(!(await policy.isEnabled()), "Reset must revoke the executing Fable access policy, not only its UI switch.")
        try check(!model.extendedFableAccessEnabled, "Reset must clear the UI consent switch.")
        try check(model.claudeCredentialIdentity == .standard, "Reset must restore the standard identity without deleting any credential.")
        try check(!model.firstRunCompleted, "Data reset must restore the first-run state.")
        try check(unregistered == 1, "Data reset must unregister login-at-startup once.")
        let reloaded = await store.load()
        try check(!reloaded.extendedFableAccessEnabled, "Reset must persist revoked consent.")
        try check(reloaded.claudeCredentialIdentity == .standard, "Reset must persist the standard identity selection.")
        await model.shutdown()
        try check(!(await policy.isEnabled()), "Shutdown after reset must not restore a queued consent grant.")
    }

    private static func resetFailureStillRevokesConsent(in directory: URL) async throws {
        enum SyntheticFailure: Error { case unregister }
        let store = SettingsStore(directoryURL: directory)
        var saved = AppSettings()
        saved.extendedFableAccessEnabled = true
        try await store.save(saved)
        let policy = ClaudeExtendedAccessPolicy()
        let model = AppModel(
            settingsStore: store,
            refreshCoordinator: coordinator(),
            extendedAccessPolicy: policy,
            unregisterLoginItem: { throw SyntheticFailure.unregister }
        )
        model.start()
        try await wait {
            let enabled = await policy.isEnabled()
            return model.settingsAreLoaded && enabled
        }
        let result = await model.resetLocalData()
        try check(result == .failed, "A failed login-item removal must be reported as an incomplete reset.")
        try check(!(await policy.isEnabled()), "An incomplete reset must still revoke Fable access before cleanup.")
        try check(!model.extendedFableAccessEnabled, "An incomplete reset must keep the consent switch off.")
        let reloaded = await store.load()
        try check(!reloaded.extendedFableAccessEnabled, "An incomplete reset must persist revoked consent before returning.")
        await model.shutdown()
    }

    private static func shutdownPersistsLatestPreferences(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        let model = AppModel(settingsStore: store, refreshCoordinator: coordinator(), unregisterLoginItem: {})
        model.start()
        try await wait { model.settingsAreLoaded }
        model.showsWidget = false
        model.appearance = .dark
        model.refreshIntervalSeconds = 300
        await model.shutdown()
        let saved = await store.load()
        try check(!saved.showsWidget, "Shutdown must preserve the latest widget visibility.")
        try check(saved.appearance == .dark, "Shutdown must preserve the latest appearance.")
        try check(saved.refreshIntervalSeconds == 300, "Shutdown must preserve the latest refresh interval.")
    }

    private static func resetRejectsReentrantConsent(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        var saved = AppSettings()
        saved.extendedFableAccessEnabled = true
        saved.claudeCredentialIdentity = .previousDejavuDefault
        try await store.save(saved)
        let policy = ClaudeExtendedAccessPolicy()
        let gate = ResetReadGate()
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: AnyUsageProvider(fetch: { await gate.fetchUsage() }),
            codexProvider: AnyUsageProvider<CodexUsageSnapshot>(fetch: { throw UsageProviderFailure.unavailable })
        )
        let model = AppModel(
            settingsStore: store,
            refreshCoordinator: coordinator,
            extendedAccessPolicy: policy,
            unregisterLoginItem: {}
        )
        model.start()
        await gate.waitUntilReadStarted()
        try check(await policy.isEnabled(), "The gated refresh must begin with previously granted Fable consent.")

        let reset = Task { await model.resetLocalData() }
        // The provider acknowledges cancellation but deliberately holds its
        // continuation. This places reset exactly inside resetState's await,
        // after consent revocation and before cleanup, without a race/sleep.
        await gate.waitUntilCancellationObserved()
        do {
            try check(model.isResettingLocalData, "Reset must remain active while its owned read is held.")
            let policyEnabled = await policy.isEnabled()
            try check(!model.extendedFableAccessEnabled && !policyEnabled, "Consent must be revoked before waiting for the active read.")
            model.extendedFableAccessEnabled = true
            model.claudeCredentialIdentity = .standard
            try check(!model.extendedFableAccessEnabled, "A reentrant consent grant must be rejected immediately by the model.")
            try check(model.claudeCredentialIdentity == .previousDejavuDefault, "Reset must reject reentrant identity changes until cleanup completes.")
            try check(!(await policy.isEnabled()), "A reentrant setting edit must not re-enable the executing access policy.")
            let duringReset = await store.load()
            try check(!duringReset.extendedFableAccessEnabled, "Consent must remain revoked on disk during reset.")
        } catch {
            await gate.release()
            _ = await reset.value
            await model.shutdown()
            throw error
        }
        await gate.release()
        try check(await reset.value == .reset, "Reset must complete after the deterministic read gate is released.")
        try check(!model.isResettingLocalData && !model.extendedFableAccessEnabled, "Completed reset must leave consent off and release its busy state.")
        try check(!(await policy.isEnabled()), "Completed reset must not apply a delayed consent grant.")
        let afterReset = await store.load()
        try check(!afterReset.extendedFableAccessEnabled, "Completed reset must persist revoked consent after the reentrant edit.")
        await model.shutdown()
    }

    private static func shutdownBeforeLoadPreservesUnchangedSettings(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        var initial = AppSettings()
        initial.firstRunCompleted = true
        initial.refreshIntervalSeconds = 180
        try await store.save(initial)
        let model = AppModel(settingsStore: store, refreshCoordinator: coordinator(), unregisterLoginItem: {})
        model.showsWidget = false
        model.claudeCredentialIdentity = .previousDejavuDefault
        await model.shutdown()
        let saved = await store.load()
        try check(!saved.showsWidget, "A pre-load user change must survive immediate shutdown.")
        try check(saved.claudeCredentialIdentity == .previousDejavuDefault, "A pre-load explicit identity choice must survive immediate shutdown.")
        try check(saved.firstRunCompleted && saved.refreshIntervalSeconds == 180, "Pre-load shutdown must preserve unchanged saved values.")
    }

    private static func identitySelectionClearsOldValuesAndPersists(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        let policy = ClaudeExtendedAccessPolicy()
        // This reader must never be used: changing a selection is not consent
        // to read Keychain, and the coordinator below is entirely synthetic.
        let reads = SyntheticCredentialReadCounter()
        let oauth = ClaudeOAuthUsageClient(credentialReader: reads)
        let providers = IdentitySwitchProviders()
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: AnyUsageProvider(fetch: { try await providers.claude() }),
            codexProvider: AnyUsageProvider(fetch: { await providers.codex() })
        )
        let model = AppModel(settingsStore: store, refreshCoordinator: coordinator,
                             extendedAccessPolicy: policy, claudeOAuthClient: oauth, unregisterLoginItem: {})
        model.start()
        try await wait { model.settingsAreLoaded && !model.isChangingClaudeIdentity && !model.isRefreshing }
        let priorCodex = model.domainState.codexSnapshot
        let checkedAt = model.domainState.updatedAt
        try check(model.domainState.claudeSnapshot?.fiveHour?.percent == 32, "The first synthetic identity must have a value before switching.")

        model.claudeCredentialIdentity = .previousDejavuDefault
        try check(model.isChangingClaudeIdentity && model.domainState.claudeSnapshot == nil, "Identity changes must immediately remove the previous Claude account value.")
        try check(model.domainState.codexSnapshot == priorCodex, "Changing Claude identity must preserve Codex immediately.")
        await providers.waitForSecondRead()
        try check(await oauth.currentCredentialIdentity == .previousDejavuDefault, "The selected identity must be applied to the actual OAuth client before reading.")
        let consentEnabled = await policy.isEnabled()
        try check(!model.extendedFableAccessEnabled && !consentEnabled, "Selecting a login must not grant extended access.")
        try check(reads.count == 0, "An identity selection must never read credential bytes without consent.")
        await providers.releaseSecondRead()
        try await wait { !model.isChangingClaudeIdentity && !model.isRefreshing && model.domainState.claudeStatus == .offline }
        try check(model.domainState.claudeSnapshot == nil, "A failed first read from the new identity must not carry values from the previous identity.")
        try check(model.domainState.codexSnapshot == priorCodex && model.domainState.updatedAt == checkedAt, "Claude-only switching must preserve the Codex snapshot and check time.")
        try check(await providers.codexCount == 1, "An identity switch must not launch another Codex read.")
        await model.shutdown()
        let saved = await store.load()
        try check(saved.claudeCredentialIdentity == .previousDejavuDefault && !saved.extendedFableAccessEnabled, "The explicit choice must persist independently of consent.")

        let restartedOAuth = ClaudeOAuthUsageClient(credentialReader: reads)
        let restarted = AppModel(settingsStore: store, refreshCoordinator: self.coordinator(),
                                 claudeOAuthClient: restartedOAuth, unregisterLoginItem: {})
        restarted.start()
        try await wait { restarted.settingsAreLoaded && !restarted.isChangingClaudeIdentity && !restarted.isRefreshing }
        try check(restarted.claudeCredentialIdentity == .previousDejavuDefault, "The explicit identity must survive restart.")
        try check(await restartedOAuth.currentCredentialIdentity == .previousDejavuDefault, "Restart must configure the saved identity before its first refresh.")
        try check(reads.count == 0, "Restart with consent off must not read credential bytes.")
        restarted.resetPreferences()
        try await wait { !restarted.isChangingClaudeIdentity && !restarted.isRefreshing }
        let resetIdentity = await restartedOAuth.currentCredentialIdentity
        try check(restarted.claudeCredentialIdentity == .standard && resetIdentity == .standard, "Reset preferences must update both persisted and live identity.")
        await restarted.shutdown()
    }

    private static func latestIdentityWinsDuringActiveRead(in directory: URL) async throws {
        let store = SettingsStore(directoryURL: directory)
        let providers = IdentitySwitchProviders(failsSecondRead: false)
        let reads = SyntheticCredentialReadCounter()
        let oauth = ClaudeOAuthUsageClient(credentialReader: reads)
        let coordinator = UsageRefreshCoordinator(
            claudeProvider: AnyUsageProvider(fetch: { try await providers.claude() }),
            codexProvider: AnyUsageProvider(fetch: { await providers.codex() })
        )
        let model = AppModel(settingsStore: store, refreshCoordinator: coordinator,
                             claudeOAuthClient: oauth, unregisterLoginItem: {})
        model.start()
        try await wait { model.settingsAreLoaded && !model.isChangingClaudeIdentity && !model.isRefreshing }
        let initialCodexCount = await providers.codexCount
        try check(model.domainState.codexStatus == .ready && initialCodexCount == 1, "The deferred Codex follow-up fixture must start with Codex already ready.")
        model.refresh(force: true, includeCodex: false)
        await providers.waitForSecondRead()
        model.claudeCredentialIdentity = .previousDejavuDefault
        await providers.waitForSecondCancellation()
        model.claudeCredentialIdentity = .standard
        model.claudeCredentialIdentity = .previousDejavuDefault
        // A Codex follow-up that arrives during the drain must be deferred,
        // not discarded. No real Codex executable is used by this fixture.
        model.refresh(force: true)
        try check(model.isChangingClaudeIdentity && model.domainState.claudeSnapshot == nil, "Superseded identity changes must keep old values hidden while draining.")
        await providers.releaseSecondRead()
        try await wait { !model.isChangingClaudeIdentity && !model.isRefreshing && model.domainState.claudeStatus == .ready }
        let finalIdentity = await oauth.currentCredentialIdentity
        try check(model.claudeCredentialIdentity == .previousDejavuDefault && finalIdentity == .previousDejavuDefault, "The latest identity must win after an older read drains.")
        try check(reads.count == 0 && !model.extendedFableAccessEnabled, "Rapid identity changes must not read credentials or grant consent.")
        try check(await providers.codexCount == 2 && model.domainState.codexStatus == .ready, "A requested Codex login follow-up during an identity drain must run once even when Codex was already ready.")
        await model.shutdown()
        try check(await store.load().claudeCredentialIdentity == .previousDejavuDefault, "Shutdown must persist only the latest explicit identity.")
    }

    private static func coordinator() -> UsageRefreshCoordinator {
        let now = Date()
        let claude = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 32, resetsAt: now.addingTimeInterval(3_600)),
            weekly: UsageLimit(percent: 61, resetsAt: now.addingTimeInterval(86_400)),
            fable: UsageLimit(percent: 73, resetsAt: now.addingTimeInterval(86_400)),
            capturedAt: now
        )
        let codex = CodexUsageSnapshot(
            weekly: UsageLimit(percent: 84, resetsAt: now.addingTimeInterval(86_400)),
            resetCredits: 7,
            resetCreditsExpireAt: now.addingTimeInterval(86_400),
            planType: "synthetic-private-plan"
        )
        return UsageRefreshCoordinator(
            claudeProvider: AnyUsageProvider(fetch: { claude }),
            codexProvider: AnyUsageProvider(fetch: { codex })
        )
    }

    private static func wait(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<300 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ProbeFailure(message: "Timed out waiting for a native app-model transition.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        checked += 1
        if !condition { throw ProbeFailure(message: message) }
    }

    private struct ProbeFailure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}

private final class SyntheticCredentialReadCounter: ClaudeCredentialReading, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func readCredential() throws -> Data {
        lock.lock()
        reads += 1
        lock.unlock()
        throw ClaudeExtendedUsageError.credentialUnavailable
    }
}

private actor IdentitySwitchProviders {
    private let failsSecondRead: Bool
    private var claudeCount = 0
    private(set) var codexCount = 0
    private var secondRead: CheckedContinuation<Void, Never>?
    private var secondStarted = false
    private var waiters = [CheckedContinuation<Void, Never>]()
    private var secondCancelled = false
    private var cancellationWaiters = [CheckedContinuation<Void, Never>]()

    init(failsSecondRead: Bool = true) { self.failsSecondRead = failsSecondRead }

    func claude() async throws -> ClaudeUsageSnapshot {
        claudeCount += 1
        if claudeCount == 2 {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    secondRead = continuation
                    secondStarted = true
                    let pending = waiters
                    waiters.removeAll()
                    for waiter in pending { waiter.resume() }
                }
            } onCancel: {
                Task { await self.observeSecondCancellation() }
            }
            if failsSecondRead { throw UsageProviderFailure.offline }
        }
        return ClaudeUsageSnapshot(fiveHour: UsageLimit(percent: 32), weekly: nil, capturedAt: Date())
    }

    func codex() -> CodexUsageSnapshot {
        codexCount += 1
        return CodexUsageSnapshot(weekly: UsageLimit(percent: 84), resetCredits: nil,
                                  resetCreditsExpireAt: nil, planType: nil)
    }

    func waitForSecondRead() async {
        if secondStarted { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseSecondRead() {
        secondRead?.resume()
        secondRead = nil
    }

    func waitForSecondCancellation() async {
        if secondCancelled { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    private func observeSecondCancellation() {
        secondCancelled = true
        let pending = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

/// A deterministic synthetic provider: it does not release its first read when
/// cancelled, so the test controls the precise reset reentrancy window.
private actor ResetReadGate {
    private var started = false
    private var cancelled = false
    private var released = false
    private var readContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters = [CheckedContinuation<Void, Never>]()
    private var cancellationWaiters = [CheckedContinuation<Void, Never>]()

    func fetchUsage() async -> ClaudeUsageSnapshot {
        if !released {
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    readContinuation = continuation
                    started = true
                    let waiters = startWaiters
                    startWaiters.removeAll()
                    for waiter in waiters { waiter.resume() }
                }
            } onCancel: {
                Task { await self.observeCancellation() }
            }
        }
        return ClaudeUsageSnapshot(fiveHour: UsageLimit(percent: 32), weekly: nil, capturedAt: Date())
    }

    func waitUntilReadStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitUntilCancellationObserved() async {
        if cancelled { return }
        await withCheckedContinuation { cancellationWaiters.append($0) }
    }

    func release() {
        released = true
        readContinuation?.resume()
        readContinuation = nil
    }

    private func observeCancellation() {
        cancelled = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
