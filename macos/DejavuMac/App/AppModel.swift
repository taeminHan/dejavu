import Combine
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
        guard state.claudeStatus == .loading || state.claudeSnapshot != nil else { return nil }
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
    @Published private(set) var claudeConnectionState = ClaudeConnectionState.notChecked
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
            guard !isApplyingLoadedSettings, !isShuttingDown else { return }
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
            if settingsAreLoaded, !isApplyingLoadedSettings, !isShuttingDown {
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
    private let refreshCoordinator: UsageRefreshCoordinator
    private let extendedAccessPolicy: ClaudeExtendedAccessPolicy
    private let claudeConnectionManager: ClaudeStatusLineConnectionManager?
    private var persistedSettings: AppSettings
    private var dirtyFieldsBeforeLoad = Set<PersistedField>()
    private var isApplyingLoadedSettings = false
    private var isShuttingDown = false
    private var hasUnsavedSettings = false
    private var saveRevision = 0
    private var refreshRevision = 0
    private var refreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    private var settingsLoadTask: Task<Void, Never>?
    private var settingsSaveTask: Task<Void, Never>?
    private var claudeConnectionTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore? = nil,
        refreshCoordinator: UsageRefreshCoordinator? = nil,
        extendedAccessPolicy: ClaudeExtendedAccessPolicy? = nil
    ) {
        let defaults = AppSettings()
        let paths = Self.localPaths()
        let policy = extendedAccessPolicy ?? ClaudeExtendedAccessPolicy(enabled: false)
        let resolvedSettingsStore = settingsStore
            ?? SettingsStore(directoryURL: paths.applicationSupport)
        self.extendedAccessPolicy = policy
        self.settingsStore = resolvedSettingsStore
        self.diagnosticsEventLog = DiagnosticsEventLog(
            directoryURL: resolvedSettingsStore.directoryURL
        )
        if settingsStore == nil, refreshCoordinator == nil {
            self.claudeConnectionManager = Self.makeClaudeConnectionManager(paths: paths)
        } else {
            self.claudeConnectionManager = nil
        }
        self.refreshCoordinator = refreshCoordinator ?? Self.makeRefreshCoordinator(
            claudeSnapshotURL: paths.claudeSnapshot,
            extendedAccessPolicy: policy
        )
        persistedSettings = defaults
        domainState = .initial
        state = UsageApplicationViewState(.initial)
        claudeMenuBarMetrics = defaults.claudeMenuBarMetrics
        showsCodexInMenuBar = defaults.showsCodexInMenuBar
        showsWidget = defaults.showsWidget
        extendedFableAccessEnabled = defaults.extendedFableAccessEnabled
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
    }

    var settings: WidgetSettingsViewState { WidgetSettingsViewState(persistedSettings) }
    var lastNotifiedUpdateVersion: String? { persistedSettings.lastNotifiedUpdateVersion }
    var localDataDirectoryURL: URL { settingsStore.directoryURL }
    var visibleProviders: [UsageProviderViewState] {
        switch serviceDisplayMode {
        case .autoDetect:
            [state.claude, state.codex].compactMap { $0 }
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
            isClaudeVisible: domainState.claudeSnapshot != nil,
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
        let accessPolicy = extendedAccessPolicy
        settingsLoadTask = Task { @MainActor [weak self] in
            let loadedSettings = await store.load()
            guard !Task.isCancelled else { return }
            guard !Task.isCancelled, let self else { return }
            finishLoadingSettings(loadedSettings)
            await accessPolicy.setEnabled(extendedFableAccessEnabled)
            guard !Task.isCancelled, !isShuttingDown else { return }
            schedulePeriodicRefresh()
            refresh(force: true)
        }
    }

    func refresh(force: Bool = true) {
        guard settingsAreLoaded, !isShuttingDown else { return }
        if refreshTask != nil, !force { return }
        if force {
            refreshTask?.cancel()
        }

        refreshRevision &+= 1
        let revision = refreshRevision
        isRefreshing = true
        let coordinator = refreshCoordinator
        refreshTask = Task { @MainActor [weak self] in
            let nextState = await coordinator.refresh(force: force)
            guard let self else { return }
            guard refreshRevision == revision else { return }
            isRefreshing = false
            refreshTask = nil
            guard !Task.isCancelled, !isShuttingDown else { return }
            apply(nextState)
        }
    }

    func rememberNotifiedUpdateVersion(_ version: String) {
        guard settingsAreLoaded, !isShuttingDown,
              AutomaticUpdatePolicy.shouldNotify(
                availableVersion: version,
                lastNotifiedVersion: persistedSettings.lastNotifiedUpdateVersion
              ) else { return }
        persistedSettings.lastNotifiedUpdateVersion = version
        hasUnsavedSettings = true
        scheduleSettingsSave()
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
        guard settingsAreLoaded, !isShuttingDown else { return }
        let defaults = AppSettings()
        applyPreferences(defaults)
        hasUnsavedSettings = true
        scheduleSettingsSave()
        updateExtendedAccessAndRefresh()
        schedulePeriodicRefresh()
    }

    func writeDiagnosticsSnapshot() async -> URL? {
        guard settingsAreLoaded, !isShuttingDown else { return nil }
        let store = DiagnosticsStore(directoryURL: settingsStore.directoryURL)
        let snapshot = DiagnosticsSnapshot(
            state: domainState,
            widget: WidgetDiagnostics(
                isVisible: showsWidget,
                topLeftX: customWidgetPosition?.topLeftX,
                topLeftY: customWidgetPosition?.topLeftY,
                width: nil,
                height: nil,
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
        guard settingsAreLoaded, !isShuttingDown else { return .failed }

        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        refreshRevision &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        await refreshCoordinator.resetState()

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
            _ = try LocalDataResetter(directoryURL: settingsStore.directoryURL).reset()
            let defaults = AppSettings()
            applyPreferences(defaults)
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

    /// The first Claude settings read happens only after this explicit user
    /// action. App startup never probes or mutates `~/.claude`.
    func connectClaudeStatusLine() {
        guard let manager = claudeConnectionManager,
              !claudeConnectionState.isBusy,
              !isShuttingDown else { return }
        claudeConnectionState = .connecting
        claudeConnectionTask = Task { @MainActor [weak self] in
            defer { self?.claudeConnectionTask = nil }
            do {
                _ = try await manager.connect()
                guard let self, !isShuttingDown else { return }
                claudeConnectionState = .connected
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

    func disconnectClaudeStatusLine() {
        guard let manager = claudeConnectionManager,
              !claudeConnectionState.isBusy,
              !isShuttingDown else { return }
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
        Task { await coordinator.cancelAndWait() }
    }

    private func apply(_ nextState: ApplicationState) {
        domainState = nextState
        state = UsageApplicationViewState(nextState)
        recordDiagnosticsEvent(.refreshCompleted, status: nextState.combinedStatus)
        publishSystemWidgetSnapshot(nextState)
    }

    private func publishSystemWidgetSnapshot(_ state: ApplicationState) {
        guard let updatedAt = state.updatedAt,
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
        isApplyingLoadedSettings = false
    }

    private func persistedFieldDidChange(_ field: PersistedField) {
        guard !isApplyingLoadedSettings, !isShuttingDown else { return }
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
        let policy = extendedAccessPolicy
        let enabled = extendedFableAccessEnabled
        Task { @MainActor [weak self] in
            await policy.setEnabled(enabled)
            self?.refresh(force: true)
        }
    }

    private func schedulePeriodicRefresh() {
        periodicRefreshTask?.cancel()
        let seconds = Int64(persistedSettings.refreshIntervalSeconds)
        periodicRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(seconds))
                } catch {
                    return
                }
                self?.refresh(force: false)
            }
        }
    }

    private func scheduleSettingsSave() {
        guard settingsAreLoaded, !isShuttingDown else { return }
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
        extendedAccessPolicy: ClaudeExtendedAccessPolicy
    ) -> UsageRefreshCoordinator {
        let claude = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: claudeSnapshotURL),
            accessPolicy: extendedAccessPolicy
        )
        let codex = CodexUsageProvider()
        return UsageRefreshCoordinator(claudeProvider: claude, codexProvider: codex)
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
        let claudeDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
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
        paths: LocalPaths
    ) -> ClaudeStatusLineConnectionManager {
        ClaudeStatusLineConnectionManager(
            configuration: ClaudeStatusLineConnectionConfiguration(
                settingsURL: paths.claudeSettings,
                applicationSupportDirectoryURL: paths.applicationSupport,
                bridgeExecutableURL: paths.bundledBridge,
                snapshotURL: paths.claudeSnapshot
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
