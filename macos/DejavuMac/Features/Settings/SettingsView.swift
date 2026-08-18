import AppKit
import DejavuDomain
import ServiceManagement
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case providers = "Providers"
    case widget = "Widget"
    case updates = "Updates"
    case privacy = "Privacy"

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .providers: "link"
        case .widget: "rectangle.on.rectangle"
        case .updates: "arrow.triangle.2.circlepath"
        case .privacy: "hand.raised"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updateCoordinator: UpdateCoordinator
    let onShowOnboarding: () -> Void

    @StateObject private var loginItem = LoginItemController()
    @State private var confirmsSettingsReset = false
    @State private var confirmsLocalDataReset = false
    @State private var providerActionMessage: String?
    @State private var dataActionMessage: String?
    @State private var isDataActionRunning = false

    @AppStorage("selectedSettingsPane")
    private var selection = SettingsPane.general

    var body: some View {
        TabView(selection: $selection) {
            generalSettings
                .tabItem {
                    Label("General", systemImage: SettingsPane.general.symbolName)
                }
                .tag(SettingsPane.general)

            providerSettings
                .tabItem {
                    Label("Providers", systemImage: SettingsPane.providers.symbolName)
                }
                .tag(SettingsPane.providers)

            widgetSettings
                .tabItem {
                    Label("Widget", systemImage: SettingsPane.widget.symbolName)
                }
                .tag(SettingsPane.widget)

            updateSettings
                .tabItem {
                    Label("Updates", systemImage: SettingsPane.updates.symbolName)
                }
                .tag(SettingsPane.updates)

            privacySettings
                .tabItem {
                    Label("Privacy", systemImage: SettingsPane.privacy.symbolName)
                }
                .tag(SettingsPane.privacy)
        }
        .tabViewStyle(.automatic)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 430, idealHeight: 470)
        .onAppear {
            loginItem.refresh()
        }
        .alert("Reset all settings?", isPresented: $confirmsSettingsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                model.resetPreferences()
            }
        } message: {
            Text("This restores display, refresh, provider, and update preferences. It does not remove provider logins or Claude configuration.")
        }
        .alert("Reset Dejavu data?", isPresented: $confirmsLocalDataReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Data", role: .destructive) {
                resetLocalData()
            }
        } message: {
            Text("Dejavu will stop refreshing, restore its managed Claude status line when safe, and remove only Dejavu settings, snapshots, diagnostics, and its installed helper. Provider logins and conversations are never removed.")
        }
    }

    private var generalSettings: some View {
        settingsForm {
            Section {
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { loginItem.isEnabled },
                        set: { loginItem.setEnabled($0) }
                    )
                )
                .disabled(loginItem.isChanging || loginItem.isUnavailable)

                if loginItem.requiresApproval {
                    Button("Open Login Items Settings…") {
                        loginItem.openSystemSettings()
                    }
                }

                if let message = loginItem.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(loginItem.hasError ? .red : .secondary)
                }

                Picker("Refresh interval", selection: $model.refreshIntervalSeconds) {
                    ForEach([60, 120, 300], id: \.self) { seconds in
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString(
                                    "%d seconds",
                                    comment: "Refresh interval in seconds"
                                ),
                                seconds
                            )
                        )
                        .tag(seconds)
                    }
                }

                Picker("Appearance", selection: $model.appearance) {
                    ForEach(ThemePreference.allCases, id: \.rawValue) { appearance in
                        Text(LocalizedStringKey(appearance.displayName)).tag(appearance)
                    }
                }
            } header: {
                Text("Application")
            } footer: {
                Text("Login items are managed by macOS and can also be changed in System Settings.")
            }

            Section {
                Button("Show Welcome…") {
                    onShowOnboarding()
                }

                Button("Reset All Settings…", role: .destructive) {
                    confirmsSettingsReset = true
                }
                .disabled(!model.settingsAreLoaded)
            } header: {
                Text("Welcome")
            } footer: {
                Text("Review how Dejavu shows local usage and protects provider data.")
            }
        }
    }

    private var providerSettings: some View {
        settingsForm {
            ProviderSettingsSection(
                provider: .claude,
                status: model.claudeStatus.displayName,
                description: "The default connection reads only 5h and weekly rate-limit fields supplied by the Claude Code status line.",
                metricOptions: [
                    MenuBarMetricOption(metric: .fiveHour, title: "5h"),
                    MenuBarMetricOption(metric: .weekly, title: "Weekly"),
                    MenuBarMetricOption(metric: .fable, title: "Fable")
                ],
                selectedMetrics: $model.claudeMenuBarMetrics
            )

            Section {
                LabeledContent("Status") {
                    Text(LocalizedStringKey(model.claudeConnectionState.displayName))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Connect Claude Status Line…") {
                        model.connectClaudeStatusLine()
                    }
                    .disabled(model.claudeConnectionState.isBusy)

                    Button("Disconnect") {
                        model.disconnectClaudeStatusLine()
                    }
                    .disabled(model.claudeConnectionState.isBusy)

                    Button("Sign In in Terminal…") {
                        prepareLoginCommand("claude", providerName: "Claude Code")
                    }

                    Link(
                        "Installation Guide…",
                        destination: URL(string: "https://docs.anthropic.com/en/docs/claude-code/getting-started")!
                    )
                }
            } header: {
                Text("Claude Code status line")
            } footer: {
                Text("Dejavu reads or changes ~/.claude/settings.json only after you choose Connect. An existing command is preserved and chained.")
            }

            Section {
                Toggle(isOn: $model.extendedFableAccessEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Fable usage")
                        Text("Allows read-only access to the Claude Code Keychain item after macOS approval.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Text("Extended Claude access")
            } footer: {
                Text("Fable uses an undocumented Claude Code usage interface and may stop working after an update. Tokens are kept only in memory and are never saved by Dejavu.")
            }

            ProviderSettingsSection(
                provider: .codex,
                status: model.codexStatus.displayName,
                description: "Uses the local Codex app-server. Dejavu never reads ChatGPT credentials directly.",
                metricOptions: [
                    MenuBarMetricOption(metric: .weekly, title: "Usage")
                ],
                selectedMetrics: Binding(
                    get: { model.showsCodexInMenuBar ? [.weekly] : [] },
                    set: { model.showsCodexInMenuBar = $0.contains(.weekly) }
                )
            )

            Section {
                HStack {
                    Button("Sign In in Terminal…") {
                        prepareLoginCommand("codex --login", providerName: "Codex")
                    }

                    Link(
                        "Installation Guide…",
                        destination: URL(string: "https://help.openai.com/en/articles/11096431")!
                    )
                }

                if let providerActionMessage {
                    Text(providerActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Provider sign-in")
            } footer: {
                Text("Dejavu copies the official login command and opens Terminal. You decide whether to run it; Dejavu never receives the resulting credentials.")
            }
        }
    }

    private var widgetSettings: some View {
        settingsForm {
            Section {
                Toggle(isOn: $model.showsWidget) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Floating Overlay")
                        Text("This optional panel is separate from the macOS system widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Section {
                LabeledContent {
                    Text("Desktop and Notification Center")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Dejavu Usage", systemImage: "square.grid.2x2")
                }
            } header: {
                Text("System Widget")
            } footer: {
                Text("Add or remove the system widget from the macOS widget gallery.")
            }

            Section {
                Picker("Density", selection: $model.widgetDensity) {
                    ForEach(WidgetDensity.allCases, id: \.rawValue) { density in
                        Text(LocalizedStringKey(density.displayName)).tag(density)
                    }
                }

                Picker("Layout", selection: $model.widgetLayout) {
                    ForEach(WidgetLayout.allCases, id: \.rawValue) { layout in
                        Text(LocalizedStringKey(layout.displayName)).tag(layout)
                    }
                }

                Picker("Services", selection: $model.serviceDisplayMode) {
                    ForEach(ServiceDisplayMode.allCases, id: \.rawValue) { mode in
                        Text(LocalizedStringKey(mode.displayName)).tag(mode)
                    }
                }

                Picker("Placement", selection: $model.widgetPlacement) {
                    ForEach(WidgetPlacement.allCases, id: \.rawValue) { placement in
                        Text(LocalizedStringKey(placement.displayName)).tag(placement)
                    }
                }

                Toggle("Show progress bars", isOn: $model.showProgress)
                    .toggleStyle(.switch)

                Toggle("Use threshold colors", isOn: $model.useThresholdColors)
                    .toggleStyle(.switch)

                ColorPicker(
                    "Background color",
                    selection: colorSelection(for: \.backgroundColor, fallback: "#1E1E20"),
                    supportsOpacity: false
                )

                ColorPicker(
                    "Accent color",
                    selection: colorSelection(for: \.accentColor, fallback: "#3A96F6"),
                    supportsOpacity: false
                )

                ColorPicker(
                    "Text color",
                    selection: colorSelection(for: \.textColor, fallback: "#AEAEB4"),
                    supportsOpacity: false
                )

                LabeledContent("Overlay opacity") {
                    HStack(spacing: 10) {
                        Text("\(Int((model.widgetOpacity * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Slider(value: $model.widgetOpacity, in: 0.55...1, step: 0.05)
                            .frame(width: 180)
                    }
                }

                Button("Reset Overlay Position") {
                    model.resetWidgetPosition()
                }
                .disabled(
                    model.widgetPlacement == .topRight
                        && model.customWidgetPosition == nil
                )

                Button("Reset Overlay Colors") {
                    model.resetWidgetColors()
                }
            } header: {
                Text("Floating Overlay options")
            } footer: {
                Text("Dragging the overlay saves its position. Edge placements remain anchored when its size changes.")
            }
        }
    }

    private var updateSettings: some View {
        settingsForm {
            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: $model.automaticUpdateChecksEnabled
                )

                HStack {
                    Button("Check for Updates…") {
                        updateCoordinator.checkForUpdates()
                    }
                    .disabled(!updateCoordinator.canCheckForUpdates)

                    if updateCoordinator.status == .checking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(verbatim: updateCoordinator.status.message)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Software updates")
            } footer: {
                Text("Automatic checks run at startup and the next local clock hour. Downloads are verified before installation.")
            }
        }
    }

    private var privacySettings: some View {
        settingsForm {
            Section {
                PrivacyRow(
                    symbol: "key.slash",
                    title: "Credentials are never stored",
                    detail: "Codex credentials are never read. Fable access reads the Claude Code Keychain item only after you enable it and keeps the token in memory."
                )
                PrivacyRow(
                    symbol: "text.bubble",
                    title: "No conversations",
                    detail: "Prompts, transcripts, browser content, and working directories are not saved."
                )
                PrivacyRow(
                    symbol: "internaldrive",
                    title: "Local usage snapshots",
                    detail: "Usage snapshots stay in your user Application Support directory."
                )
            } header: {
                Text("Data on this Mac")
            } footer: {
                Text("Dejavu has no server and does not send your usage data to us.")
            }

            Section {
                Button("Create Diagnostics Snapshot…") {
                    createDiagnosticsSnapshot()
                }
                .disabled(isDataActionRunning)

                Button("Open Dejavu Data Folder") {
                    NSWorkspace.shared.open(model.localDataDirectoryURL)
                }

                Button("Reset Dejavu Data…", role: .destructive) {
                    confirmsLocalDataReset = true
                }
                .disabled(isDataActionRunning || !model.settingsAreLoaded)

                if isDataActionRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                if let dataActionMessage {
                    Text(dataActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Support and local data")
            } footer: {
                Text("The diagnostics snapshot contains only allow-listed status, percentage, timestamp, and overlay fields. It contains no credentials, paths, prompts, or conversations.")
            }
        }
    }

    private func settingsForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .controlSize(.regular)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func prepareLoginCommand(_ command: String, providerName: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(command, forType: .string) else {
            providerActionMessage = NSLocalizedString(
                "The login command could not be copied.",
                comment: "Provider login clipboard failure"
            )
            return
        }

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        guard NSWorkspace.shared.open(terminalURL) else {
            providerActionMessage = NSLocalizedString(
                "The login command was copied, but Terminal could not be opened.",
                comment: "Provider login Terminal failure"
            )
            return
        }
        providerActionMessage = String(
            format: NSLocalizedString(
                "The %@ login command was copied. Paste it in Terminal and press Return.",
                comment: "Provider login command ready; argument is provider name"
            ),
            providerName
        )
    }

    private func colorSelection(
        for keyPath: ReferenceWritableKeyPath<AppModel, String>,
        fallback: String
    ) -> Binding<Color> {
        Binding(
            get: {
                Color(dejavuHex: model[keyPath: keyPath])
                    ?? Color(dejavuHex: fallback)
                    ?? .accentColor
            },
            set: { color in
                guard let hex = color.dejavuHexString else { return }
                model[keyPath: keyPath] = hex
            }
        )
    }

    private func createDiagnosticsSnapshot() {
        guard !isDataActionRunning else { return }
        isDataActionRunning = true
        Task { @MainActor in
            defer { isDataActionRunning = false }
            guard let url = await model.writeDiagnosticsSnapshot() else {
                dataActionMessage = NSLocalizedString(
                    "The diagnostics snapshot could not be created.",
                    comment: "Diagnostics write failure"
                )
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dataActionMessage = NSLocalizedString(
                "A privacy-safe diagnostics snapshot was created.",
                comment: "Diagnostics write success"
            )
        }
    }

    private func resetLocalData() {
        guard !isDataActionRunning else { return }
        isDataActionRunning = true
        Task { @MainActor in
            defer { isDataActionRunning = false }
            switch await model.resetLocalData() {
            case .reset:
                dataActionMessage = NSLocalizedString(
                    "Dejavu local data was reset.",
                    comment: "Local data reset success"
                )
            case .claudeConflict:
                dataActionMessage = NSLocalizedString(
                    "Nothing was removed because the Claude status line changed after Dejavu connected it. Disconnect it manually or restore the managed value first.",
                    comment: "Local data reset blocked by Claude configuration conflict"
                )
            case .failed:
                dataActionMessage = NSLocalizedString(
                    "Dejavu local data could not be reset safely. Nothing outside the Dejavu data folder was removed.",
                    comment: "Local data reset failure"
                )
            }
        }
    }
}

private extension Color {
    var dejavuHexString: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let red = Int((min(1, max(0, color.redComponent)) * 255).rounded())
        let green = Int((min(1, max(0, color.greenComponent)) * 255).rounded())
        let blue = Int((min(1, max(0, color.blueComponent)) * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

@MainActor
private final class LoginItemController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var isChanging = false
    @Published private(set) var isUnavailable = false
    @Published private(set) var hasError = false
    @Published private(set) var message: String?

    private let service = SMAppService.mainApp

    init() {
        refresh()
    }

    func refresh() {
        isUnavailable = false
        hasError = false
        switch service.status {
        case .enabled:
            isEnabled = true
            requiresApproval = false
            message = nil
        case .requiresApproval:
            isEnabled = false
            requiresApproval = true
            message = NSLocalizedString(
                "Allow Dejavu in System Settings to open it automatically.",
                comment: "Login item requires approval"
            )
        case .notRegistered:
            isEnabled = false
            requiresApproval = false
            message = nil
        case .notFound:
            isEnabled = false
            requiresApproval = false
            isUnavailable = true
            message = NSLocalizedString(
                "Login item registration is unavailable for this app installation.",
                comment: "Login item unavailable"
            )
        @unknown default:
            isEnabled = false
            requiresApproval = false
            isUnavailable = true
            message = NSLocalizedString(
                "The login item status could not be determined.",
                comment: "Unknown login item status"
            )
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard !isChanging else { return }
        isChanging = true
        hasError = false
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            message = nil
        } catch {
            hasError = true
            message = enabled
                ? NSLocalizedString(
                    "Dejavu could not be added to Login Items.",
                    comment: "Login item registration failure"
                )
                : NSLocalizedString(
                    "Dejavu could not be removed from Login Items.",
                    comment: "Login item unregistration failure"
                )
        }
        isChanging = false
        refreshPreservingError()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func refreshPreservingError() {
        let previousMessage = message
        let previousHasError = hasError
        refresh()
        if previousHasError {
            message = previousMessage
            hasError = true
        }
    }
}

private struct ProviderSettingsSection: View {
    let provider: ProviderBrand
    let status: String
    let description: String
    let metricOptions: [MenuBarMetricOption]
    @Binding var selectedMetrics: [MenuBarMetric]

    var body: some View {
        Section {
            LabeledContent {
                Label {
                    Text(LocalizedStringKey(status))
                } icon: {
                    Image(systemName: statusSymbol)
                }
                .foregroundStyle(.secondary)
            } label: {
                Text("Status")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Menu bar metrics")
                HStack(spacing: 16) {
                    ForEach(metricOptions) { option in
                        Toggle(
                            LocalizedStringKey(option.title),
                            isOn: selection(for: option.metric)
                        )
                        .toggleStyle(.checkbox)
                    }
                }
            }
        } header: {
            ProviderBrandLabel(provider: provider, iconSize: 14)
        } footer: {
            Text(LocalizedStringKey(description))
        }
    }

    private func selection(for metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { selectedMetrics.contains(metric) },
            set: { isSelected in
                if isSelected {
                    if !selectedMetrics.contains(metric) {
                        selectedMetrics.append(metric)
                    }
                } else {
                    selectedMetrics.removeAll { $0 == metric }
                }
            }
        )
    }

    private var statusSymbol: String {
        switch status {
        case "Ready": "checkmark.circle"
        case "Login required": "person.crop.circle.badge.exclamationmark"
        default: "circle.dashed"
        }
    }
}

private extension ThemePreference {
    var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

private extension WidgetDensity {
    var displayName: String {
        switch self {
        case .small: "Small"
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        }
    }
}

private extension WidgetLayout {
    var displayName: String {
        switch self {
        case .singleRow: "One row"
        case .twoRows: "Two rows"
        }
    }
}

private extension ServiceDisplayMode {
    var displayName: String {
        switch self {
        case .autoDetect: "Automatic"
        case .claudeAndCodex: "Claude and Codex"
        case .claudeOnly: "Claude only"
        case .codexOnly: "Codex only"
        }
    }
}

private extension WidgetPlacement {
    var displayName: String {
        switch self {
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        case .custom: "Custom"
        }
    }
}

private struct MenuBarMetricOption: Identifiable {
    let metric: MenuBarMetric
    let title: String

    var id: MenuBarMetric { metric }
}

private struct PrivacyRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                Text(LocalizedStringKey(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .accessibilityElement(children: .combine)
    }
}
