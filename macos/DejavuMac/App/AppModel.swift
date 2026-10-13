import Combine
import AppKit
import Network
import ServiceManagement
import Foundation
import WidgetKit
import DejavuApplication
import DejavuDomain
import DejavuPersistence
import DejavuProviders
import DejavuWidgetShared

extension UsageStatus {
    var displayName: String {
        switch self {
        case .loading: "Refreshing"
        case .ready: "Ready"
        case .loginRequired: "Login required"
        case .rateLimited: "Rate limited"
        case .offline: "Offline"
        case .error: "Unavailable"
        case .unavailable: "Not connected"
        }
    }
}

struct UsageLimitViewState: Identifiable {
    let id: String
    let label: String
    let usageLimit: UsageLimit?

    init(id: String, label: String, usageLimit: UsageLimit?) {
        self.id = id
        self.label = label
        self.usageLimit = usageLimit
    }

    var displayPercent: Double? { usageLimit?.displayPercent }
    var resetsAt: Date? { usageLimit?.resetsAt }

    var displayText: String {
        guard let displayPercent else { return "--%" }
        return "\(Int(displayPercent.rounded()))%"
    }
}

struct UsageProviderViewState: Identifiable {
    enum Kind: String {
        case claude = "Claude"
        case codex = "Codex"

        var brand: ProviderBrand {
            switch self {
            case .claude: .claude
            case .codex: .codex
            }
        }

        var providerID: UsageProviderID {
            switch self {
            case .claude: .claude
            case .codex: .codex
            }
        }
    }

    var id: Kind { kind }
    let kind: Kind
    let status: UsageStatus
    let message: String?
    let limits: [UsageLimitViewState]
    let planName: String?
    let resetCredits: Int?
    let resetCreditsExpireAt: Date?
}

struct UsageApplicationViewState {
    var claude: UsageProviderViewState?
    var codex: UsageProviderViewState?
    var updatedAt: Date?

    init(_ state: ApplicationState) {
        updatedAt = state.updatedAt
        claude = Self.claudeProvider(from: state)
        codex = Self.codexProvider(from: state)
    }

    private static func claudeProvider(from state: ApplicationState) -> UsageProviderViewState? {
        guard (state.claudeStatus == .loading && state.claudeIssue != .waitingForData)
            || state.claudeSnapshot != nil else { return nil }
        let snapshot = state.claudeSnapshot
        return UsageProviderViewState(
            kind: .claude,
            status: state.claudeStatus,
            message: state.claudeMessage.isEmpty ? nil : state.claudeMessage,
            limits: [
                UsageLimitViewState(
                    id: "claude-five-hour",
                    label: "5 hour",
                    usageLimit: snapshot?.fiveHour
                ),
                UsageLimitViewState(
                    id: "claude-weekly",
                    label: "Weekly",
                    usageLimit: snapshot?.weekly
                ),
                UsageLimitViewState(
                    id: "claude-fable",
                    label: "Fable",
                    usageLimit: snapshot?.fable
                )
            ],
            planName: nil,
            resetCredits: nil,
            resetCreditsExpireAt: nil
        )
    }

    private static func codexProvider(from state: ApplicationState) -> UsageProviderViewState? {
        guard state.codexStatus == .loading || state.codexSnapshot != nil else { return nil }
        let snapshot = state.codexSnapshot
        return UsageProviderViewState(
            kind: .codex,
            status: state.codexStatus,
            message: state.codexMessage.isEmpty ? nil : state.codexMessage,
            limits: [
                UsageLimitViewState(
                    id: "codex-usage",
                    label: "Usage",
                    usageLimit: snapshot?.weekly
                )
            ],
            planName: snapshot?.planType,
            resetCredits: snapshot?.resetCredits,
            resetCreditsExpireAt: snapshot?.resetCreditsExpireAt
        )
    }
}

struct WidgetSettingsViewState {
    let densityName: String
    let layoutName: String
    let servicePolicyName: String
    let placementName: String
    let refreshIntervalName: String
    let showsProgress: Bool
    let usesThresholdColors: Bool

    init(_ settings: AppSettings) {
        densityName = switch settings.widgetDensity {
        case .small: "Small"
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        }
        layoutName = settings.widgetLayout == .singleRow ? "One row" : "Two rows"
        servicePolicyName = switch settings.serviceDisplayMode {
        case .autoDetect: "Automatic"
        case .claudeAndCodex: "Claude and Codex"
        case .claudeOnly: "Claude only"
        case .codexOnly: "Codex only"
        }
        placementName = switch settings.widgetPlacement {
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .custom: "Custom"
        }
        refreshIntervalName = "\(settings.refreshIntervalSeconds) seconds"
        showsProgress = settings.showProgress
        usesThresholdColors = settings.useThresholdColors
    }
}

@MainActor
final class AppModel: ObservableObject {
    enum LocalDataResetResult: Equatable {
        case reset
        case claudeConflict
        case failed
    }

    enum ClaudeConnectionState: Equatable {
        case notChecked
        case connecting
        case connected
        case disconnecting
        case disconnected
        case conflict
        case failed

        var displayName: String {
            switch self {
            case .notChecked: "Not checked"
            case .connecting: "Connecting…"
            case .connected: "Connected"
            case .disconnecting: "Disconnecting…"
            case .disconnected: "Not connected"
            case .conflict: "Review required"
            case .failed: "Connection failed"
            }
        }

        var isBusy: Bool { self == .connecting || self == .disconnecting }
    }

    private enum PersistedField: Hashable {
        case claudeMenuBarMetrics
        case showsCodexInMenuBar
        case showsWidget
        case extendedFableAccessEnabled
        case claudeCredentialIdentity
        case automaticUpdateChecksEnabled
        case showProgress
        case useThresholdColors
        case backgroundColor
        case accentColor
        case textColor
        case widgetOpacity
        case refreshIntervalSeconds
        case widgetDensity
        case widgetLayout
        case serviceDisplayMode
        case widgetPlacement
        case customWidgetPosition
        case appearance
    }

    @Published private(set) var state: UsageApplicationViewState
    @Published private(set) var domainState: ApplicationState
    @Published private(set) var isRefreshing = false
    @Published private(set) var settingsAreLoaded = false
    @Published private(set) var isResettingLocalData = false
    @Published private(set) var claudeConnectionState = ClaudeConnectionState.notChecked
    @Published private(set) var firstRunCompleted = false
    @Published private(set) var claudeLoginPending = false
    @Published private(set) var isChangingClaudeIdentity = false
    @Published private(set) var codexLoginPending = false
    @Published private(set) var claudeLoginMessage: String?
    @Published private(set) var codexLoginMessage: String?
    @Published private(set) var claudeConnectionMessage: String?
    var widgetFrame: CGRect?
    @Published var claudeMenuBarMetrics: [MenuBarMetric] {
        didSet {
            let normalized = Self.normalizedClaudeMetrics(claudeMenuBarMetrics)
            if claudeMenuBarMetrics != normalized {
                claudeMenuBarMetrics = normalized
                return
            }
            persistedFieldDidChange(.claudeMenuBarMetrics)
        }
    }
    @Published var showsCodexInMenuBar: Bool {
        didSet { persistedFieldDidChange(.showsCodexInMenuBar) }
    }
    @Published var showsWidget: Bool {
        didSet { persistedFieldDidChange(.showsWidget) }
    }
    @Published var extendedFableAccessEnabled: Bool {
        didSet {
            persistedFieldDidChange(.extendedFableAccessEnabled)
            guard !isApplyingLoadedSettings, !isShuttingDown, !isResettingLocalData else { return }
            updateExtendedAccessAndRefresh()
        }
    }
    @Published var claudeCredentialIdentity: ClaudeCredentialIdentity {
        didSet {
            guard oldValue != claudeCredentialIdentity, !isApplyingLoadedSettings else { return }
            // A running official login owns its selected destination until it
            // finishes. Never silently redirect the reader mid-login.
            if claudeLoginPending {
                isApplyingLoadedSettings = true
                claudeCredentialIdentity = oldValue
                isApplyingLoadedSettings = false
                return
            }
            persistedFieldDidChange(.claudeCredentialIdentity)
            guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData else { return }
            claudeLoginMessage = nil
            updateExtendedAccessAndRefresh()
        }
    }
    @Published var automaticUpdateChecksEnabled: Bool {
        didSet { persistedFieldDidChange(.automaticUpdateChecksEnabled) }
    }
    @Published var showProgress: Bool {
        didSet { persistedFieldDidChange(.showProgress) }
    }
    @Published var useThresholdColors: Bool {
        didSet { persistedFieldDidChange(.useThresholdColors) }
    }
    @Published var backgroundColor: String {
        didSet { persistedFieldDidChange(.backgroundColor) }
    }
    @Published var accentColor: String {
        didSet { persistedFieldDidChange(.accentColor) }
    }
    @Published var textColor: String {
        didSet { persistedFieldDidChange(.textColor) }
    }
    @Published var widgetOpacity: Double {
        didSet { persistedFieldDidChange(.widgetOpacity) }
    }
    @Published var refreshIntervalSeconds: Int {
        didSet {
            persistedFieldDidChange(.refreshIntervalSeconds)
            if settingsAreLoaded, !isApplyingLoadedSettings, !isShuttingDown, !isResettingLocalData {
                schedulePeriodicRefresh()
            }
        }
    }
    @Published var widgetDensity: WidgetDensity {
        didSet { persistedFieldDidChange(.widgetDensity) }
    }
    @Published var widgetLayout: WidgetLayout {
        didSet { persistedFieldDidChange(.widgetLayout) }
    }
    @Published var serviceDisplayMode: ServiceDisplayMode {
        didSet { persistedFieldDidChange(.serviceDisplayMode) }
    }
    @Published var widgetPlacement: WidgetPlacement {
        didSet { persistedFieldDidChange(.widgetPlacement) }
    }
    @Published private(set) var customWidgetPosition: WidgetPosition? {
        didSet { persistedFieldDidChange(.customWidgetPosition) }
    }
    @Published var appearance: ThemePreference {
        didSet { persistedFieldDidChange(.appearance) }
    }

    private let settingsStore: SettingsStore
    private let diagnosticsEventLog: DiagnosticsEventLog
    private let diagnosticsStore: DiagnosticsStore
    private let refreshCoordinator: UsageRefreshCoordinator
    private let extendedAccessPolicy: ClaudeExtendedAccessPolicy
    private let claudeConnectionManager: ClaudeStatusLineConnectionManager?
    private let codexUsageProvider: CodexUsageProvider
    private let claudeOAuthClient: ClaudeOAuthUsageClient
    private let codexAuthentication = CodexAuthenticationService()
    private var persistedSettings: AppSettings
    private var dirtyFieldsBeforeLoad = Set<PersistedField>()
    private var isApplyingLoadedSettings = false
    private var isShuttingDown = false
    private var hasUnsavedSettings = false
    private var saveRevision = 0
    private var refreshRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var pendingCodexRefresh = false
    private var periodicRefreshTask: Task<Void, Never>?
    private var settingsLoadTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var claudeConnectionTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var accessPolicyTask: Task<Void, Never>?
    private var accessPolicyRevision = 0
    private var claudeLoginTask: Task<Void, Never>?
    private var codexLoginTask: Task<Void, Never>?
    private var refreshSchedule = UsageRefreshSchedule()
    private var lifecycleObservers = [NSObjectProtocol]()
    private var networkMonitor: NWPathMonitor?
    private let monitorsLifecycle: Bool
    private let unregisterLoginItem: @MainActor () throws -> Void
    private let isPreview: Bool

    init(
        settingsStore: SettingsStore? = nil,
        refreshCoordinator: UsageRefreshCoordinator? = nil,
        extendedAccessPolicy: ClaudeExtendedAccessPolicy? = nil,
        claudeOAuthClient: ClaudeOAuthUsageClient? = nil,
        unregisterLoginItem: (@MainActor () throws -> Void)? = nil,
        previewState: ApplicationState? = nil,
        previewSettings: AppSettings = AppSettings()
    ) {
        let defaults = AppSettings()
        let paths = Self.localPaths()
        let policy = extendedAccessPolicy ?? ClaudeExtendedAccessPolicy(enabled: false)
        self.isPreview = previewState != nil
        let resolvedSettingsStore = settingsStore
            ?? SettingsStore(directoryURL: previewState == nil ? paths.applicationSupport
                : FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-preview-\(UUID().uuidString)/dejavu"))
        self.extendedAccessPolicy = policy
        let codex = CodexUsageProvider()
        self.codexUsageProvider = codex
        let oauth = claudeOAuthClient ?? ClaudeOAuthUsageClient()
        self.claudeOAuthClient = oauth
        self.settingsStore = resolvedSettingsStore
        self.diagnosticsEventLog = DiagnosticsEventLog(
            directoryURL: resolvedSettingsStore.directoryURL
        )
        self.diagnosticsStore = DiagnosticsStore(directoryURL: resolvedSettingsStore.directoryURL)
        self.monitorsLifecycle = previewState == nil && settingsStore == nil && refreshCoordinator == nil
        self.unregisterLoginItem = unregisterLoginItem ?? {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval: try SMAppService.mainApp.unregister()
            default: break
            }
        }
        if previewState == nil, settingsStore == nil, refreshCoordinator == nil {
            self.claudeConnectionManager = Self.makeClaudeConnectionManager(paths: paths)
        } else {
            self.claudeConnectionManager = nil
        }
        if let previewState {
            self.refreshCoordinator = UsageRefreshCoordinator(
                claudeProvider: AnyUsageProvider<ClaudeUsageSnapshot>(fetch: { throw UsageProviderFailure.unavailable }),
                codexProvider: AnyUsageProvider<CodexUsageSnapshot>(fetch: { throw UsageProviderFailure.unavailable }),
                initialState: previewState
            )
        } else {
            self.refreshCoordinator = refreshCoordinator ?? Self.makeRefreshCoordinator(
                claudeSnapshotURL: paths.claudeSnapshot, extendedAccessPolicy: policy,
                codexProvider: codex, extendedClient: oauth
            )
        }
        persistedSettings = defaults
        domainState = .initial
        state = UsageApplicationViewState(.initial)
        claudeMenuBarMetrics = defaults.claudeMenuBarMetrics
        showsCodexInMenuBar = defaults.showsCodexInMenuBar
        showsWidget = defaults.showsWidget
        extendedFableAccessEnabled = defaults.extendedFableAccessEnabled
        claudeCredentialIdentity = defaults.claudeCredentialIdentity
        automaticUpdateChecksEnabled = defaults.automaticUpdateChecksEnabled
        showProgress = defaults.showProgress
        useThresholdColors = defaults.useThresholdColors
        backgroundColor = defaults.backgroundColor
        accentColor = defaults.accentColor
        textColor = defaults.textColor
        widgetOpacity = defaults.widgetOpacity
        refreshIntervalSeconds = defaults.refreshIntervalSeconds
        widgetDensity = defaults.widgetDensity
        widgetLayout = defaults.widgetLayout
        serviceDisplayMode = defaults.serviceDisplayMode
        widgetPlacement = defaults.widgetPlacement
        customWidgetPosition = defaults.customPosition
        appearance = defaults.appearance
        if let previewState {
            applyPreferences(previewSettings)
            domainState = previewState
            state = UsageApplicationViewState(previewState)
            settingsAreLoaded = true
        }
    }

    var settings: WidgetSettingsViewState { WidgetSettingsViewState(persistedSettings) }
    var lastNotifiedUpdateVersion: String? { persistedSettings.lastNotifiedUpdateVersion }
    var localDataDirectoryURL: URL { settingsStore.directoryURL }
    var visibleProviders: [UsageProviderViewState] {
        switch serviceDisplayMode {
        case .autoDetect:
            [state.claude ?? (claudeConnectionState == .connected ? visibleClaudeProvider : nil), state.codex].compactMap { $0 }
        case .claudeAndCodex:
            [visibleClaudeProvider, visibleCodexProvider]
        case .claudeOnly:
            [visibleClaudeProvider]
        case .codexOnly:
            [visibleCodexProvider]
        }
    }
    var claudeStatus: UsageStatus { domainState.claudeStatus }
    var codexStatus: UsageStatus { domainState.codexStatus }
    var customClaudeProfile: Bool {
        ClaudeConfigurationPaths().directoryURL != FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true).standardizedFileURL
    }
    var customProfileSupportsFable: Bool { !customClaudeProfile }
    var usesSyntheticData: Bool { isPreview }

    private var visibleClaudeProvider: UsageProviderViewState {
        state.claude ?? UsageProviderViewState(
            kind: .claude,
            status: domainState.claudeStatus,
            message: domainState.claudeMessage.isEmpty ? nil : domainState.claudeMessage,
            limits: [
                UsageLimitViewState(id: "claude-five-hour", label: "5 hour", usageLimit: nil),
                UsageLimitViewState(id: "claude-weekly", label: "Weekly", usageLimit: nil),
                UsageLimitViewState(id: "claude-fable", label: "Fable", usageLimit: nil)
            ],
            planName: nil,
            resetCredits: nil,
            resetCreditsExpireAt: nil
        )
    }

    private var visibleCodexProvider: UsageProviderViewState {
        state.codex ?? UsageProviderViewState(
            kind: .codex,
            status: domainState.codexStatus,
            message: domainState.codexMessage.isEmpty ? nil : domainState.codexMessage,
            limits: [
                UsageLimitViewState(id: "codex-usage", label: "Usage", usageLimit: nil)
            ],
            planName: nil,
            resetCredits: nil,
            resetCreditsExpireAt: nil
        )
    }

    var statusItemTitle: String {
        statusItemSummary(
            domainState: domainState,
            claudeMetrics: claudeMenuBarMetrics,
            showsCodex: showsCodexInMenuBar
        ).accessibilityTitle
    }

    /// `@Published` emits its new value before the stored property changes.
    /// StatusItemController passes the emitted values here so a metric choice
    /// updates the menu bar synchronously instead of reading the previous
    /// property value and waiting for another state change.
    func statusItemTitle(
        domainState: ApplicationState,
        claudeMetrics: [MenuBarMetric],
        showsCodex: Bool
    ) -> String {
        statusItemSummary(
            domainState: domainState,
            claudeMetrics: claudeMetrics,
            showsCodex: showsCodex
        ).accessibilityTitle
    }

    func statusItemSummary(
        domainState: ApplicationState,
        claudeMetrics: [MenuBarMetric],
        showsCodex: Bool
    ) -> MenuBarSummary {
        MenuBarSummaryFormatter.summary(
            claudeFiveHour: domainState.claudeSnapshot?.fiveHour,
            claudeWeekly: domainState.claudeSnapshot?.weekly,
            claudeFable: domainState.claudeSnapshot?.fable,
            isClaudeVisible: domainState.claudeSnapshot != nil
                || (domainState.claudeStatus == .loading && domainState.claudeIssue != .waitingForData)
                || claudeConnectionState == .connected,
            codexWeekly: domainState.codexSnapshot?.weekly,
            isCodexVisible: domainState.codexSnapshot != nil,
            claudeMetrics: Self.normalizedClaudeMetrics(claudeMetrics),
            showsCodex: showsCodex
        )
    }

    var statusItemAccessibilityValue: String {
        statusItemTitle.isEmpty ? "No usage metric shown" : statusItemTitle
    }

    func start() {
        guard settingsLoadTask == nil, !settingsAreLoaded, !isShuttingDown else { return }
        let store = settingsStore
        settingsLoadTask = Task { @MainActor [weak self] in
            let loadedSettings = await store.load()
            guard !Task.isCancelled else { return }
            guard !Task.isCancelled, let self else { return }
            finishLoadingSettings(loadedSettings)
            if let manager = claudeConnectionManager {
                do {
                    let result = try await manager.upgradeInstalledBridgeIfOwned()
                    claudeConnectionState = result == .notConnected ? .notChecked : .connected
                } catch {
                    claudeConnectionState = .failed
                }
            }
            guard !Task.isCancelled, !isShuttingDown else { return }
            schedulePeriodicRefresh()
            startLifecycleMonitoring()
            updateExtendedAccessAndRefresh()
        }
    }

    func refresh(force: Bool = true, includeCodex: Bool = true) {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData, !isPreview else { return }
        if isChangingClaudeIdentity {
            // Preserve an official Codex-login follow-up that arrives while
            // Claude's identity change is draining an older provider request.
            pendingCodexRefresh = pendingCodexRefresh || includeCodex
            return
        }
        if refreshTask != nil, !force { return }
        if force {
            refreshTask?.cancel()
        }

        refreshRevision &+= 1
        let revision = refreshRevision
        isRefreshing = true
        let coordinator = refreshCoordinator
        refreshTask = Task { @MainActor [weak self] in
            let nextState = await coordinator.refresh(force: force, includeCodex: includeCodex)
            guard let self else { return }
            guard refreshRevision == revision else { return }
            isRefreshing = false
            refreshTask = nil
            guard !Task.isCancelled, !isShuttingDown else { return }
            apply(nextState, reschedule: includeCodex)
        }
    }

    func rememberNotifiedUpdateVersion(_ version: String) {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData,
              AutomaticUpdatePolicy.shouldNotify(
                availableVersion: version,
                lastNotifiedVersion: persistedSettings.lastNotifiedUpdateVersion
              ) else { return }
        persistedSettings.lastNotifiedUpdateVersion = version
        hasUnsavedSettings = true
        scheduleSettingsSave()
    }

    func refreshManually() {
        guard !isPreview, !isShuttingDown, !isResettingLocalData, !isChangingClaudeIdentity else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await claudeOAuthClient.resetRetryBackoff()
            refresh(force: true)
        }
    }

    func checkClaudeProjectSettings() {
        guard !isPreview, !isShuttingDown, !isResettingLocalData else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let paths = Self.localPaths()
        let manager = Self.makeClaudeConnectionManager(paths: paths, projectFolder: folder)
        Task { @MainActor [weak self] in
            do {
                let warnings = try await manager.preflight()
                self?.claudeConnectionMessage = NSLocalizedString(warnings.isEmpty
                    ? "No conflicting project settings found."
                    : "Project or managed settings may override collection. Review Claude settings.", comment: "Claude preflight")
            } catch {
                self?.claudeConnectionMessage = NSLocalizedString("Claude settings could not be checked safely.", comment: "Claude preflight failed")
            }
        }
    }

    func markOnboardingCompleted() {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData else { return }
        firstRunCompleted = true
        persistedSettings.firstRunCompleted = true
        hasUnsavedSettings = true
        scheduleSettingsSave()
    }

    private enum LoginLaunchError: Error { case unavailable }

    private nonisolated static func openLoginBrowser(_ url: URL) async throws {
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if !opened { throw LoginLaunchError.unavailable }
    }

    func loginCodex() {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData, !isPreview else { return }
        let service = codexAuthentication
        if codexLoginPending {
            Task { try? await service.reopenBrowserIfPending(openBrowser: Self.openLoginBrowser) }
            return
        }
        codexLoginPending = true
        codexLoginMessage = NSLocalizedString("Complete sign-in in your browser.", comment: "Codex login")
        codexLoginTask = Task { @MainActor [weak self] in
            defer { self?.codexLoginPending = false; self?.codexLoginTask = nil }
            do {
                try await service.login(openBrowser: Self.openLoginBrowser)
                guard let self, !isShuttingDown, !Task.isCancelled else { return }
                await codexUsageProvider.authenticationCompleted()
                codexLoginMessage = NSLocalizedString("Signed in. Checking usage…", comment: "Login completed")
                refresh(force: true)
            } catch is CancellationError {
                self?.codexLoginMessage = nil
            } catch {
                self?.codexLoginMessage = NSLocalizedString(
                    "Sign-in could not finish. Check that the CLI is installed and try again.", comment: "Login failed"
                )
            }
        }
    }

    func cancelCodexLogin() {
        codexLoginTask?.cancel()
        Task { await codexAuthentication.cancel() }
    }

    func loginClaude() {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData,
              !isChangingClaudeIdentity, !claudeLoginPending, !isPreview else { return }
        do {
            let command = try ClaudeLoginCommandBuilder().command(credentialIdentity: claudeCredentialIdentity)
            // A private, short-lived script starts the official CLI directly.
            // Neither credentials nor auth URLs are copied to the clipboard.
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dejavu-auth-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            let script = directory.appendingPathComponent("Claude Login.command")
            let result = directory.appendingPathComponent("result")
            let quotedResult = "'" + result.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            try ("#!/bin/zsh\n" + command + "\ndejavu_auth_result=$?\nprintf '%s' \"$dejavu_auth_result\" > "
                 + quotedResult + "\nexit \"$dejavu_auth_result\"\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            guard NSWorkspace.shared.open(script) else {
                try? FileManager.default.removeItem(at: directory)
                throw LoginLaunchError.unavailable
            }
            claudeLoginPending = true
            claudeLoginMessage = NSLocalizedString("Complete Claude sign-in in Terminal.", comment: "Claude login")
            claudeLoginTask = Task { @MainActor [weak self] in
                defer {
                    try? FileManager.default.removeItem(at: directory)
                    self?.claudeLoginPending = false
                    self?.claudeLoginTask = nil
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(300))
                while !Task.isCancelled, ContinuousClock.now < deadline {
                    if let status = try? String(contentsOf: result, encoding: .utf8) {
                        guard let self, !isShuttingDown else { return }
                        claudeLoginMessage = NSLocalizedString(status == "0"
                            ? "Signed in. Start a Claude Code session to receive usage."
                            : "Claude sign-in did not finish. Try again.", comment: "Claude login result")
                        refresh(force: true)
                        return
                    }
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    self?.refresh(force: false, includeCodex: self?.domainState.codexStatus == .loading)
                }
                self?.claudeLoginMessage = NSLocalizedString("Sign-in timed out. Try again.", comment: "Login timeout")
            }
        } catch ClaudeLoginCommandError.unsupportedCredentialIdentity {
            claudeLoginMessage = NSLocalizedString(
                "Previous Dejavu sign-in is available only for the default Claude profile.", comment: "Unsupported Claude login identity"
            )
        } catch {
            claudeLoginMessage = NSLocalizedString("Install Claude Code or check Terminal, then try again.", comment: "Claude launch failed")
        }
    }

    func applicationDidBecomeActive() {
        guard settingsAreLoaded, !isShuttingDown else { return }
        if claudeLoginPending || codexLoginPending || domainState.claudeStatus == .loginRequired
            || domainState.codexStatus == .loginRequired {
            nudgeRefresh()
        }
    }

    func rememberWidgetPosition(
        displayIdentifier: String?,
        topLeftX: Double,
        topLeftY: Double
    ) {
        customWidgetPosition = WidgetPosition(
            displayIdentifier: displayIdentifier,
            topLeftX: topLeftX,
            topLeftY: topLeftY
        )
        widgetPlacement = .custom
    }

    func resetWidgetPosition() {
        customWidgetPosition = nil
        widgetPlacement = .topRight
    }

    func resetWidgetColors() {
        let defaults = AppSettings()
        backgroundColor = defaults.backgroundColor
        accentColor = defaults.accentColor
        textColor = defaults.textColor
    }

    func resetPreferences() {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData, !claudeLoginPending else { return }
        let defaults = AppSettings()
        applyPreferences(defaults)
        hasUnsavedSettings = true
        scheduleSettingsSave()
        updateExtendedAccessAndRefresh()
        schedulePeriodicRefresh()
    }

    func writeDiagnosticsSnapshot() async -> URL? {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData else { return nil }
        let store = diagnosticsStore
        let snapshot = DiagnosticsSnapshot(
            state: domainState,
            widget: WidgetDiagnostics(
                isVisible: showsWidget,
                topLeftX: widgetFrame.map { Double($0.minX) } ?? customWidgetPosition?.topLeftX,
                topLeftY: widgetFrame.map { Double($0.maxY) } ?? customWidgetPosition?.topLeftY,
                width: widgetFrame.map { Double($0.width) },
                height: widgetFrame.map { Double($0.height) },
                placement: widgetPlacement,
                backgroundOpacity: widgetOpacity
            )
        )
        do {
            try await store.write(snapshot)
            return store.statusURL
        } catch {
            return nil
        }
    }

    func resetLocalData() async -> LocalDataResetResult {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData, !isPreview else { return .failed }
        isResettingLocalData = true
        defer {
            isResettingLocalData = false
            schedulePeriodicRefresh()
            refresh(force: true)
        }
        // Drain any older snapshot before persisting revoked consent. A
        // queued save must never restore pre-reset consent after a failure.
        settingsSaveTask?.cancel()
        await settingsSaveTask?.value
        settingsSaveTask = nil
        saveRevision &+= 1
        codexLoginTask?.cancel()
        claudeLoginTask?.cancel()
        await codexAuthentication.cancel()
        await claudeLoginTask?.value

        accessPolicyTask?.cancel()
        await accessPolicyTask?.value
        accessPolicyRevision &+= 1
        isChangingClaudeIdentity = false
        await extendedAccessPolicy.setEnabled(false)
        isApplyingLoadedSettings = true
        extendedFableAccessEnabled = false
        persistedSettings.extendedFableAccessEnabled = false
        isApplyingLoadedSettings = false
        hasUnsavedSettings = true
        do {
            // Revocation must survive even if later bridge/login-item cleanup
            // fails or the app is interrupted before its final save.
            try await settingsStore.save(persistedSettings)
            hasUnsavedSettings = false
        } catch { return .failed }

        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        refreshRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        await refreshCoordinator.resetState()
        diagnosticsTask?.cancel()
        await diagnosticsTask?.value
        diagnosticsTask = nil

        let pendingConnectionTask = claudeConnectionTask
        await pendingConnectionTask?.value
        claudeConnectionTask = nil
        if let claudeConnectionManager {
            do {
                _ = try await claudeConnectionManager.disconnect()
            } catch let error as ClaudeStatusLineConnectionError where error == .conflict {
                schedulePeriodicRefresh()
                refresh(force: true)
                return .claudeConflict
            } catch {
                schedulePeriodicRefresh()
                refresh(force: true)
                return .failed
            }
        }

        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        saveRevision &+= 1
        do {
            try unregisterLoginItem()
            _ = try LocalDataResetter(directoryURL: settingsStore.directoryURL).reset()
            let defaults = AppSettings()
            applyPreferences(defaults)
            await claudeOAuthClient.setCredentialIdentity(defaults.claudeCredentialIdentity)
            try await settingsStore.save(defaults)
            hasUnsavedSettings = false
            claudeConnectionState = .disconnected
            domainState = .initial
            state = UsageApplicationViewState(.initial)
            recordDiagnosticsEvent(.localDataReset, status: .unavailable)
            schedulePeriodicRefresh()
            refresh(force: true)
            return .reset
        } catch {
            schedulePeriodicRefresh()
            refresh(force: true)
            return .failed
        }
    }

    /// Claude settings are read only after explicit Connect or project-check
    /// actions. Startup upgrades only the already-owned local helper.
    func connectClaudeStatusLine() {
        guard let manager = claudeConnectionManager,
              !claudeConnectionState.isBusy,
              !isShuttingDown, !isResettingLocalData else { return }
        claudeConnectionState = .connecting
        claudeConnectionTask = Task { @MainActor [weak self] in
            defer { self?.claudeConnectionTask = nil }
            do {
                _ = try await manager.connect()
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = .connected
                let warnings = try await manager.preflight()
                claudeConnectionMessage = NSLocalizedString(warnings.isEmpty
                    ? "Connected. Start a Claude Code session to receive usage."
                    : "Connected. Review project or hook settings if usage does not arrive.", comment: "Claude collector connected")
                refresh(force: true)
            } catch let error as ClaudeStatusLineConnectionError {
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = error == .conflict || error == .managedSettingsOverride ? .conflict : .failed
            } catch {
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = .failed
            }
        }
    }

    func disconnectClaudeStatusLine() {
        guard let manager = claudeConnectionManager,
              !claudeConnectionState.isBusy,
              !isShuttingDown, !isResettingLocalData else { return }
        claudeConnectionState = .disconnecting
        claudeConnectionTask = Task { @MainActor [weak self] in
            defer { self?.claudeConnectionTask = nil }
            do {
                _ = try await manager.disconnect()
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = .disconnected
                refresh(force: true)
            } catch let error as ClaudeStatusLineConnectionError {
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = error == .conflict ? .conflict : .failed
            } catch {
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = .failed
            }
        }
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        settingsLoadTask?.cancel()
        settingsLoadTask = nil
        settingsSaveTask?.cancel()
        settingsSaveTask = nil
        let pendingClaudeConnectionTask = claudeConnectionTask
        await pendingClaudeConnectionTask?.value
        claudeConnectionTask = nil
        await refreshCoordinator.cancelAndWait()
        codexLoginTask?.cancel()
        claudeLoginTask?.cancel()
        await codexAuthentication.shutdown()
        await claudeLoginTask?.value
        await codexUsageProvider.shutdown()
        stopLifecycleMonitoring()
        await diagnosticsTask?.value
        diagnosticsTask = nil
        accessPolicyTask?.cancel()
        await accessPolicyTask?.value

        if !settingsAreLoaded, !dirtyFieldsBeforeLoad.isEmpty {
            var loadedSettings = await settingsStore.load()
            mergeDirtyFields(into: &loadedSettings)
            try? await settingsStore.save(loadedSettings)
            dirtyFieldsBeforeLoad.removeAll()
            hasUnsavedSettings = false
            return
        }

        guard settingsAreLoaded, hasUnsavedSettings else { return }
        try? await settingsStore.save(persistedSettings)
        hasUnsavedSettings = false
    }

    func cancelOwnedTasksForImmediateTermination() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        periodicRefreshTask?.cancel()
        refreshTask?.cancel()
        settingsLoadTask?.cancel()
        settingsSaveTask?.cancel()
        claudeConnectionTask?.cancel()
        periodicRefreshTask = nil
        refreshTask = nil
        settingsLoadTask = nil
        settingsSaveTask = nil
        claudeConnectionTask = nil
        let coordinator = refreshCoordinator
        stopLifecycleMonitoring()
        diagnosticsTask?.cancel()
        accessPolicyTask?.cancel()
        codexLoginTask?.cancel()
        claudeLoginTask?.cancel()
        let authentication = codexAuthentication
        Task { await authentication.shutdown() }
        Task { await coordinator.cancelAndWait() }
    }

    private func apply(_ nextState: ApplicationState, reschedule: Bool = true) {
        domainState = nextState
        state = UsageApplicationViewState(nextState)
        recordDiagnosticsEvent(.refreshCompleted, status: nextState.combinedStatus)
        publishSystemWidgetSnapshot(nextState)
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            _ = await self?.writeDiagnosticsSnapshot()
        }
        if reschedule {
            refreshSchedule.completed(state: nextState, interval: TimeInterval(refreshIntervalSeconds))
            armPeriodicRefresh()
        } else if let retryAt = nextState.retryAt, retryAt > Date() {
            refreshSchedule.bringForward(after: retryAt.timeIntervalSinceNow + 0.5)
            armPeriodicRefresh()
        }
    }

    private func publishSystemWidgetSnapshot(_ state: ApplicationState) {
        guard monitorsLifecycle, let updatedAt = state.updatedAt,
              let store = WidgetSnapshotStore.appGroup(identifier: Self.appGroupIdentifier) else {
            return
        }
        let snapshot = WidgetUsageSnapshot(
            state: state,
            updatedAt: updatedAt,
            includesClaude: state.claudeSnapshot != nil,
            includesCodex: state.codexSnapshot != nil
        )
        do {
            try store.write(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.usageKind)
        } catch {
            // An unsigned development build may not have an App Group
            // container. Provider state remains available in the main app.
        }
    }

    private func finishLoadingSettings(_ loadedSettings: AppSettings) {
        guard !isShuttingDown else { return }
        settingsLoadTask = nil

        var mergedSettings = loadedSettings
        isApplyingLoadedSettings = true
        if !dirtyFieldsBeforeLoad.contains(.claudeMenuBarMetrics) {
            claudeMenuBarMetrics = loadedSettings.claudeMenuBarMetrics
        }
        if !dirtyFieldsBeforeLoad.contains(.showsCodexInMenuBar) {
            showsCodexInMenuBar = loadedSettings.showsCodexInMenuBar
        }
        if !dirtyFieldsBeforeLoad.contains(.showsWidget) {
            showsWidget = loadedSettings.showsWidget
        }
        if !dirtyFieldsBeforeLoad.contains(.extendedFableAccessEnabled) {
            extendedFableAccessEnabled = loadedSettings.extendedFableAccessEnabled
        }
        if !dirtyFieldsBeforeLoad.contains(.claudeCredentialIdentity) {
            claudeCredentialIdentity = loadedSettings.claudeCredentialIdentity
        }
        if !dirtyFieldsBeforeLoad.contains(.automaticUpdateChecksEnabled) {
            automaticUpdateChecksEnabled = loadedSettings.automaticUpdateChecksEnabled
        }
        if !dirtyFieldsBeforeLoad.contains(.showProgress) {
            showProgress = loadedSettings.showProgress
        }
        if !dirtyFieldsBeforeLoad.contains(.useThresholdColors) {
            useThresholdColors = loadedSettings.useThresholdColors
        }
        if !dirtyFieldsBeforeLoad.contains(.backgroundColor) {
            backgroundColor = loadedSettings.backgroundColor
        }
        if !dirtyFieldsBeforeLoad.contains(.accentColor) {
            accentColor = loadedSettings.accentColor
        }
        if !dirtyFieldsBeforeLoad.contains(.textColor) {
            textColor = loadedSettings.textColor
        }
        if !dirtyFieldsBeforeLoad.contains(.widgetOpacity) {
            widgetOpacity = loadedSettings.widgetOpacity
        }
        if !dirtyFieldsBeforeLoad.contains(.refreshIntervalSeconds) {
            refreshIntervalSeconds = loadedSettings.refreshIntervalSeconds
        }
        if !dirtyFieldsBeforeLoad.contains(.widgetDensity) {
            widgetDensity = loadedSettings.widgetDensity
        }
        if !dirtyFieldsBeforeLoad.contains(.widgetLayout) {
            widgetLayout = loadedSettings.widgetLayout
        }
        if !dirtyFieldsBeforeLoad.contains(.serviceDisplayMode) {
            serviceDisplayMode = loadedSettings.serviceDisplayMode
        }
        if !dirtyFieldsBeforeLoad.contains(.widgetPlacement) {
            widgetPlacement = loadedSettings.widgetPlacement
        }
        if !dirtyFieldsBeforeLoad.contains(.customWidgetPosition) {
            customWidgetPosition = loadedSettings.customPosition
        }
        if !dirtyFieldsBeforeLoad.contains(.appearance) {
            appearance = loadedSettings.appearance
        }
        mergeDirtyFields(into: &mergedSettings)

        persistedSettings = mergedSettings
        firstRunCompleted = mergedSettings.firstRunCompleted
        isApplyingLoadedSettings = false
        settingsAreLoaded = true
        recordDiagnosticsEvent(.appStarted, status: domainState.combinedStatus)

        if dirtyFieldsBeforeLoad.isEmpty {
            hasUnsavedSettings = false
        } else {
            hasUnsavedSettings = true
            scheduleSettingsSave()
        }
        dirtyFieldsBeforeLoad.removeAll()
    }

    private func applyPreferences(_ settings: AppSettings) {
        isApplyingLoadedSettings = true
        claudeMenuBarMetrics = settings.claudeMenuBarMetrics
        showsCodexInMenuBar = settings.showsCodexInMenuBar
        showsWidget = settings.showsWidget
        extendedFableAccessEnabled = settings.extendedFableAccessEnabled
        claudeCredentialIdentity = settings.claudeCredentialIdentity
        automaticUpdateChecksEnabled = settings.automaticUpdateChecksEnabled
        showProgress = settings.showProgress
        useThresholdColors = settings.useThresholdColors
        backgroundColor = settings.backgroundColor
        accentColor = settings.accentColor
        textColor = settings.textColor
        widgetOpacity = settings.widgetOpacity
        refreshIntervalSeconds = settings.refreshIntervalSeconds
        widgetDensity = settings.widgetDensity
        widgetLayout = settings.widgetLayout
        serviceDisplayMode = settings.serviceDisplayMode
        widgetPlacement = settings.widgetPlacement
        customWidgetPosition = settings.customPosition
        appearance = settings.appearance
        persistedSettings = settings
        firstRunCompleted = settings.firstRunCompleted
        isApplyingLoadedSettings = false
    }

    private func persistedFieldDidChange(_ field: PersistedField) {
        guard !isApplyingLoadedSettings, !isShuttingDown else { return }
        guard !isResettingLocalData else {
            // Reset is a consent-revoking transaction. Reject reentrant UI
            // edits while actor-backed cleanup yields the main actor.
            applyPreferences(persistedSettings)
            return
        }
        guard settingsAreLoaded else {
            dirtyFieldsBeforeLoad.insert(field)
            return
        }

        switch field {
        case .claudeMenuBarMetrics:
            persistedSettings.claudeMenuBarMetrics = claudeMenuBarMetrics
        case .showsCodexInMenuBar:
            persistedSettings.showsCodexInMenuBar = showsCodexInMenuBar
        case .showsWidget:
            persistedSettings.showsWidget = showsWidget
        case .extendedFableAccessEnabled:
            persistedSettings.extendedFableAccessEnabled = extendedFableAccessEnabled
        case .claudeCredentialIdentity:
            persistedSettings.claudeCredentialIdentity = claudeCredentialIdentity
        case .automaticUpdateChecksEnabled:
            persistedSettings.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        case .showProgress:
            persistedSettings.showProgress = showProgress
        case .useThresholdColors:
            persistedSettings.useThresholdColors = useThresholdColors
        case .backgroundColor:
            persistedSettings.backgroundColor = backgroundColor
        case .accentColor:
            persistedSettings.accentColor = accentColor
        case .textColor:
            persistedSettings.textColor = textColor
        case .widgetOpacity:
            persistedSettings.widgetOpacity = widgetOpacity
        case .refreshIntervalSeconds:
            persistedSettings.refreshIntervalSeconds = refreshIntervalSeconds
        case .widgetDensity:
            persistedSettings.widgetDensity = widgetDensity
        case .widgetLayout:
            persistedSettings.widgetLayout = widgetLayout
        case .serviceDisplayMode:
            persistedSettings.serviceDisplayMode = serviceDisplayMode
        case .widgetPlacement:
            persistedSettings.widgetPlacement = widgetPlacement
        case .customWidgetPosition:
            persistedSettings.customPosition = customWidgetPosition
        case .appearance:
            persistedSettings.appearance = appearance
        }
        hasUnsavedSettings = true
        scheduleSettingsSave()
    }

    private func mergeDirtyFields(into settings: inout AppSettings) {
        if dirtyFieldsBeforeLoad.contains(.claudeMenuBarMetrics) {
            settings.claudeMenuBarMetrics = claudeMenuBarMetrics
        }
        if dirtyFieldsBeforeLoad.contains(.showsCodexInMenuBar) {
            settings.showsCodexInMenuBar = showsCodexInMenuBar
        }
        if dirtyFieldsBeforeLoad.contains(.showsWidget) {
            settings.showsWidget = showsWidget
        }
        if dirtyFieldsBeforeLoad.contains(.extendedFableAccessEnabled) {
            settings.extendedFableAccessEnabled = extendedFableAccessEnabled
        }
        if dirtyFieldsBeforeLoad.contains(.claudeCredentialIdentity) {
            settings.claudeCredentialIdentity = claudeCredentialIdentity
        }
        if dirtyFieldsBeforeLoad.contains(.automaticUpdateChecksEnabled) {
            settings.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        }
        if dirtyFieldsBeforeLoad.contains(.showProgress) {
            settings.showProgress = showProgress
        }
        if dirtyFieldsBeforeLoad.contains(.useThresholdColors) {
            settings.useThresholdColors = useThresholdColors
        }
        if dirtyFieldsBeforeLoad.contains(.backgroundColor) {
            settings.backgroundColor = backgroundColor
        }
        if dirtyFieldsBeforeLoad.contains(.accentColor) {
            settings.accentColor = accentColor
        }
        if dirtyFieldsBeforeLoad.contains(.textColor) {
            settings.textColor = textColor
        }
        if dirtyFieldsBeforeLoad.contains(.widgetOpacity) {
            settings.widgetOpacity = widgetOpacity
        }
        if dirtyFieldsBeforeLoad.contains(.refreshIntervalSeconds) {
            settings.refreshIntervalSeconds = refreshIntervalSeconds
        }
        if dirtyFieldsBeforeLoad.contains(.widgetDensity) {
            settings.widgetDensity = widgetDensity
        }
        if dirtyFieldsBeforeLoad.contains(.widgetLayout) {
            settings.widgetLayout = widgetLayout
        }
        if dirtyFieldsBeforeLoad.contains(.serviceDisplayMode) {
            settings.serviceDisplayMode = serviceDisplayMode
        }
        if dirtyFieldsBeforeLoad.contains(.widgetPlacement) {
            settings.widgetPlacement = widgetPlacement
        }
        if dirtyFieldsBeforeLoad.contains(.customWidgetPosition) {
            settings.customPosition = customWidgetPosition
        }
        if dirtyFieldsBeforeLoad.contains(.appearance) {
            settings.appearance = appearance
        }
    }

    private func updateExtendedAccessAndRefresh() {
        guard settingsAreLoaded, !isShuttingDown, !isResettingLocalData, !isPreview else { return }
        let policy = extendedAccessPolicy
        let oauth = claudeOAuthClient
        let coordinator = refreshCoordinator
        let enabled = extendedFableAccessEnabled
        let identity = claudeCredentialIdentity
        accessPolicyRevision &+= 1
        let revision = accessPolicyRevision
        accessPolicyTask?.cancel()

        // Hide old-account values synchronously, before any actor hop. The
        // coordinator is then drained so a late response cannot restore them.
        refreshRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        isChangingClaudeIdentity = true
        let cleared = ApplicationState(
            combinedStatus: .loading,
            claudeStatus: .loading,
            claudeMessage: "Checking Claude usage",
            codexStatus: domainState.codexStatus,
            codexMessage: domainState.codexMessage,
            codexSnapshot: domainState.codexSnapshot,
            updatedAt: domainState.updatedAt,
            codexIssue: domainState.codexIssue
        )
        apply(cleared, reschedule: false)
        accessPolicyTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            await policy.setEnabled(false)
            guard !Task.isCancelled, revision == accessPolicyRevision, !isShuttingDown, !isResettingLocalData else { return }
            await oauth.setCredentialIdentity(identity)
            guard !Task.isCancelled, revision == accessPolicyRevision, !isShuttingDown, !isResettingLocalData else { return }
            _ = await coordinator.resetClaudeState()
            guard !Task.isCancelled, revision == accessPolicyRevision, !isShuttingDown, !isResettingLocalData else { return }
            await policy.setEnabled(enabled)
            guard !Task.isCancelled, revision == accessPolicyRevision, !isShuttingDown, !isResettingLocalData else { return }
            isChangingClaudeIdentity = false
            accessPolicyTask = nil
            // Changing Claude's identity is not a reason to restart Codex.
            let includeCodex = pendingCodexRefresh || domainState.codexStatus == .loading
            pendingCodexRefresh = false
            refresh(force: true, includeCodex: includeCodex)
        }
    }

    private func schedulePeriodicRefresh() {
        refreshSchedule.bringForward(after: TimeInterval(persistedSettings.refreshIntervalSeconds))
        armPeriodicRefresh()
    }

    private func armPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        guard let deadline = refreshSchedule.deadline, !isShuttingDown else { return }
        periodicRefreshTask = Task { @MainActor [weak self] in
            do { try await ContinuousClock().sleep(until: deadline) } catch { return }
            guard let self, !Task.isCancelled, !isShuttingDown else { return }
            refreshSchedule.consume()
            if refreshTask != nil {
                refreshSchedule.bringForward(after: 5)
                armPeriodicRefresh()
            } else {
                refresh(force: false)
            }
        }
    }

    private func nudgeRefresh() {
        guard settingsAreLoaded, !isShuttingDown else { return }
        refreshSchedule.bringForward(after: 5)
        armPeriodicRefresh()
    }

    private func startLifecycleMonitoring() {
        guard monitorsLifecycle, networkMonitor == nil else { return }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            lifecycleObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.nudgeRefresh() }
            })
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, [.offline, .error].contains(domainState.claudeStatus)
                    || [.offline, .error].contains(domainState.codexStatus) else { return }
                nudgeRefresh()
            }
        }
        networkMonitor = monitor
        monitor.start(queue: DispatchQueue(label: "dev.taemtaem.dejavu.network-recovery"))
    }

    private func stopLifecycleMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        for observer in lifecycleObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        lifecycleObservers.removeAll()
    }

    private func scheduleSettingsSave() {
        guard settingsAreLoaded, !isShuttingDown, !isPreview else { return }
        settingsSaveTask?.cancel()
        saveRevision += 1

        let revision = saveRevision
        let snapshot = persistedSettings
        let store = settingsStore
        settingsSaveTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            do {
                try await store.save(snapshot)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.settingsSaveCompleted(revision: revision)
        }
    }

    private func recordDiagnosticsEvent(
        _ kind: DiagnosticsEventKind,
        status: UsageStatus?
    ) {
        let log = diagnosticsEventLog
        let event = DiagnosticsEvent(recordedAt: Date(), kind: kind, status: status)
        Task {
            try? await log.append(event)
        }
    }

    private func settingsSaveCompleted(revision: Int) {
        guard revision == saveRevision else { return }
        settingsSaveTask = nil
        hasUnsavedSettings = false
    }

    private static func makeRefreshCoordinator(
        claudeSnapshotURL: URL,
        extendedAccessPolicy: ClaudeExtendedAccessPolicy,
        codexProvider: CodexUsageProvider,
        extendedClient: ClaudeOAuthUsageClient
    ) -> UsageRefreshCoordinator {
        let claude = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: claudeSnapshotURL),
            extendedProvider: extendedClient,
            accessPolicy: extendedAccessPolicy
        )
        return UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codexProvider)
    }

    private static func normalizedClaudeMetrics(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        MenuBarMetric.allCases.filter { metric in
            metric != .hidden && metrics.contains(metric)
        }
    }

    private typealias LocalPaths = (
        applicationSupport: URL,
        claudeSnapshot: URL,
        claudeSettings: URL,
        bundledBridge: URL
    )

    private static func localPaths() -> LocalPaths {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directory = base.appendingPathComponent("dejavu", isDirectory: true)
        let claudeDirectory = ClaudeConfigurationPaths().directoryURL
        return (
            applicationSupport: directory,
            claudeSnapshot: directory.appendingPathComponent("claude-status.json", isDirectory: false),
            claudeSettings: claudeDirectory.appendingPathComponent("settings.json", isDirectory: false),
            bundledBridge: Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Helpers/dejavu-claude-bridge",
                isDirectory: false
            )
        )
    }

    private static func makeClaudeConnectionManager(
        paths: LocalPaths,
        projectFolder: URL? = nil
    ) -> ClaudeStatusLineConnectionManager {
        ClaudeStatusLineConnectionManager(
            configuration: ClaudeStatusLineConnectionConfiguration(
                settingsURL: paths.claudeSettings,
                applicationSupportDirectoryURL: paths.applicationSupport,
                bridgeExecutableURL: paths.bundledBridge,
                snapshotURL: paths.claudeSnapshot,
                preflightSettings: [ClaudePreflightSettingsFile(
                    url: URL(fileURLWithPath: "/Library/Application Support/ClaudeCode/managed-settings.json"), scope: .managed
                )] + (projectFolder.map { folder in
                    [".claude/settings.json", ".claude/settings.local.json"].map {
                        ClaudePreflightSettingsFile(url: folder.appendingPathComponent($0), scope: .project)
                    }
                } ?? [])
            )
        )
    }

    private static var appGroupIdentifier: String {
        guard let configured = Bundle.main.object(
            forInfoDictionaryKey: "DEJAVUAppGroupIdentifier"
        ) as? String else {
            return WidgetConstants.defaultAppGroupIdentifier
        }
        let value = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? WidgetConstants.defaultAppGroupIdentifier : value
    }
}
