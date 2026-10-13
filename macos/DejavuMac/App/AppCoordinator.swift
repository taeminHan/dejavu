import AppKit
import Combine
import DejavuDomain
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let model: AppModel
    let updateCoordinator: UpdateCoordinator
    private let statusItemController: StatusItemController
    private let widgetPanelController: WidgetPanelController

    private var detailsPopover: NSPopover?
    private var escapeMonitor: Any?
    private var restoresStatusFocus = false
    private weak var detailsPreviousKeyWindow: NSWindow?
    private weak var detailsPreviousFirstResponder: NSResponder?
    private var lastDetailsDismissal = Date.distantPast
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var widgetVisibilityObservation: AnyCancellable?
    private var updateSettingObservation: AnyCancellable?
    private var appearanceObservation: AnyCancellable?
    private var firstRunObservation: AnyCancellable?
    private var isStopped = false

    var automaticUpdateChecksEnabled: Bool { model.automaticUpdateChecksEnabled }

    func applicationDidBecomeActive() {
        model.applicationDidBecomeActive()
    }

    init(model: AppModel) {
        self.model = model
        updateCoordinator = UpdateCoordinator()
        statusItemController = StatusItemController(model: model, updateCoordinator: updateCoordinator)
        widgetPanelController = WidgetPanelController(model: model)
        super.init()

        updateCoordinator.onRememberNotifiedVersion = { [weak model] version in
            model?.rememberNotifiedUpdateVersion(version)
        }

        statusItemController.onShowDetails = { [weak self] in self?.toggleDetails() }
        statusItemController.onShowSettings = { [weak self] in self?.showSettings() }
        statusItemController.onRefresh = { [weak self] in self?.model.refreshManually() }
        statusItemController.onQuit = { NSApp.terminate(nil) }
        widgetPanelController.onOpenDetails = { [weak self] in self?.showDetails() }
    }

    func start(arguments: [String]) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: .dejavuOpenSettings,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: .dejavuActivateExisting,
            object: nil
        )

        statusItemController.start()
        updateSettingObservation = Publishers.CombineLatest(
            model.$settingsAreLoaded,
            model.$automaticUpdateChecksEnabled
        )
            .filter { settingsAreLoaded, _ in settingsAreLoaded }
            .sink { [weak self] _, enabled in
                guard let self else { return }
                updateCoordinator.start(
                    automaticallyChecksForUpdates: enabled,
                    lastNotifiedVersion: model.lastNotifiedUpdateVersion
                )
            }
        widgetVisibilityObservation = Publishers.CombineLatest(
            model.$settingsAreLoaded,
            model.$showsWidget
        )
        .sink { [weak self] settingsAreLoaded, showsWidget in
            guard let self, settingsAreLoaded else { return }
            if showsWidget {
                widgetPanelController.show()
            } else {
                widgetPanelController.hide()
            }
        }
        appearanceObservation = Publishers.CombineLatest(
            model.$settingsAreLoaded,
            model.$appearance
        )
        .filter { settingsAreLoaded, _ in settingsAreLoaded }
        .sink { _, appearance in
            Self.applyAppearance(appearance)
        }
        model.start()

        if !arguments.contains("--settings"), !arguments.contains("--details") {
            firstRunObservation = Publishers.CombineLatest(model.$settingsAreLoaded, model.$firstRunCompleted)
                .filter { loaded, _ in loaded }
                .prefix(1)
                .sink { [weak self] _, completed in
                    guard !completed else { return }
                    self?.showOnboarding()
                }
        }

        if arguments.contains("--onboarding") {
            showOnboarding()
        } else if arguments.contains("--settings") {
            showSettings()
        } else if arguments.contains("--details") {
            showDetails()
        }
    }

    func prepareForTermination() async {
        guard !isStopped else { return }
        widgetVisibilityObservation?.cancel()
        widgetVisibilityObservation = nil
        updateSettingObservation?.cancel()
        updateSettingObservation = nil
        appearanceObservation?.cancel()
        appearanceObservation = nil
        firstRunObservation?.cancel()
        firstRunObservation = nil
        await model.shutdown()
        stopUI()
    }

    func stop() {
        guard !isStopped else { return }
        widgetVisibilityObservation?.cancel()
        widgetVisibilityObservation = nil
        updateSettingObservation?.cancel()
        updateSettingObservation = nil
        appearanceObservation?.cancel()
        appearanceObservation = nil
        firstRunObservation?.cancel()
        firstRunObservation = nil
        model.cancelOwnedTasksForImmediateTermination()
        stopUI()
    }

    private func stopUI() {
        guard !isStopped else { return }
        isStopped = true
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        updateCoordinator.stop()
        statusItemController.stop()
        widgetPanelController.close()
        closeDetails()
        settingsWindowController?.window?.close()
        onboardingWindowController?.window?.close()
    }

    func showDetails() {
        guard let button = statusItemController.statusButton else { return }
        if detailsPopover == nil {
            let rootView = UsageDetailsView(
                model: model,
                onOpenSettings: { [weak self] in self?.showSettings() },
                onOpenConnections: { [weak self] in self?.showSettings(pane: "Providers") },
                onOpenUpdates: { [weak self] in self?.showSettings(pane: "Updates") }
            )
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            popover.contentSize = NSSize(width: 430, height: 560)
            popover.contentViewController = NSHostingController(rootView: rootView)
            popover.delegate = self
            detailsPopover = popover
        }
        guard let detailsPopover, !detailsPopover.isShown else { return }
        detailsPopover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        detailsPreviousKeyWindow = NSApp.keyWindow
        detailsPreviousFirstResponder = NSApp.keyWindow?.firstResponder
        NSApp.activate()
        detailsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        detailsPopover.contentViewController?.view.window?.makeKey()
        if let view = detailsPopover.contentViewController?.view {
            view.window?.makeFirstResponder(view)
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                self?.restoresStatusFocus = true
                self?.closeDetails()
            }
            return nil
        }
    }

    private func toggleDetails() {
        if detailsPopover?.isShown == true {
            restoresStatusFocus = NSApp.currentEvent?.type == .keyDown
            closeDetails()
        } else {
            // A transient popover may close on mouse-down before the status
            // button's mouse-up action. Do not reopen it for that same click.
            guard Date().timeIntervalSince(lastDetailsDismissal) > 0.3 else { return }
            showDetails()
        }
    }

    private func closeDetails() {
        detailsPopover?.performClose(nil)
        removeEscapeMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        lastDetailsDismissal = Date()
        statusItemController.statusButton?.highlight(false)
        removeEscapeMonitor()
        if restoresStatusFocus {
            if let window = detailsPreviousKeyWindow {
                window.makeKey()
                window.makeFirstResponder(detailsPreviousFirstResponder)
            } else if let button = statusItemController.statusButton {
                button.window?.makeFirstResponder(button)
            }
        }
        detailsPreviousKeyWindow = nil
        detailsPreviousFirstResponder = nil
        restoresStatusFocus = false
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    func showSettings(pane: String? = nil) {
        closeDetails()
        if let pane {
            UserDefaults.standard.set(pane, forKey: "selectedSettingsPane")
        }
        if settingsWindowController == nil {
            let rootView = SettingsView(
                model: model,
                updateCoordinator: updateCoordinator,
                onShowOnboarding: { [weak self] in self?.showOnboarding() }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            configureAuxiliaryWindow(window, title: "Dejavu Settings")
            window.minSize = NSSize(width: 700, height: 500)
            window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.contentViewController = NSHostingController(rootView: rootView)
            settingsWindowController = NSWindowController(window: window)
        }
        present(settingsWindowController)
    }

    func showOnboarding() {
        if onboardingWindowController == nil {
            let rootView = OnboardingView(model: model, onFinish: { [weak self] in
                self?.model.markOnboardingCompleted()
                self?.onboardingWindowController?.window?.orderOut(nil)
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            configureAuxiliaryWindow(window, title: "Welcome to Dejavu")
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: rootView)
            onboardingWindowController = NSWindowController(window: window)
        }
        present(onboardingWindowController)
    }

    func windowWillClose(_ notification: Notification) {
        guard !isStopped,
              let window = notification.object as? NSWindow,
              window === onboardingWindowController?.window else { return }
        model.markOnboardingCompleted()
    }

    @discardableResult
    func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "dejavu",
              url.host?.lowercased() == "usage",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.path.isEmpty || url.path == "/",
              url.query == nil,
              url.fragment == nil else {
            return false
        }

        showDetails()
        return true
    }

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        showSettings()
    }

    private func configureAuxiliaryWindow(_ window: NSWindow, title: String) {
        window.title = NSLocalizedString(title, comment: "Dejavu window title")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.center()
    }

    private func present(_ controller: NSWindowController?) {
        guard let controller else { return }
        NSApp.activate()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private static func applyAppearance(_ appearance: ThemePreference) {
        NSApp.appearance = switch appearance {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

extension AppCoordinator {
    /// Exercises actual SwiftUI/AppKit trees without starting providers,
    /// reading user settings, registering login items, or starting Sparkle.
    /// This is structural and off-screen rendering evidence, not VoiceOver
    /// or installed-app update acceptance.
    static func runNativeUIValidation(outputDirectory: URL? = nil) -> Bool {
        let appearances: [ThemePreference] = [.system, .light, .dark]
        let statuses = UsageStatus.allCases
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let claude = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 48, resetsAt: timestamp.addingTimeInterval(3600)),
            weekly: UsageLimit(percent: 73, resetsAt: timestamp.addingTimeInterval(86400)),
            fable: UsageLimit(percent: 91, resetsAt: timestamp.addingTimeInterval(86400)),
            capturedAt: timestamp
        )
        let codex = CodexUsageSnapshot(
            weekly: UsageLimit(percent: 88, resetsAt: timestamp.addingTimeInterval(86400)),
            resetCredits: 0,
            resetCreditsExpireAt: timestamp.addingTimeInterval(86400),
            planType: "Plus"
        )
        func providerMessage(_ name: String, status: UsageStatus) -> String {
            switch status {
            case .ready: "\(name) usage is current"
            case .loading: "Checking \(name) usage"
            case .loginRequired: "\(name) sign-in is required"
            case .rateLimited: "\(name) is temporarily rate limited"
            case .offline: "\(name) is offline"
            case .error: "\(name) usage could not be read"
            case .unavailable: "\(name) is unavailable"
            }
        }
        var failures = 0
        var detailCount = 0
        var settingsCount = 0
        var onboardingCount = 0
        var floatingCount = 0
        let captureWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        captureWindow.isReleasedWhenClosed = false
        captureWindow.title = "Dejavu — Synthetic UI Validation"
        if let outputDirectory {
            do { try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true) }
            catch { print("Native UI validation: output directory unavailable"); return false }
        }

        func render<V: View>(_ root: V, size: NSSize, appearance: ThemePreference, locale: String, name: String, capture: Bool = false) {
            let host = NSHostingView(rootView: root
                .environment(\.locale, Locale(identifier: locale))
                .preferredColorScheme(appearance == .dark ? .dark : appearance == .light ? .light : nil))
            let window = capture && outputDirectory != nil ? captureWindow
                : NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = appearance == .dark ? NSAppearance(named: .darkAqua)
                : appearance == .light ? NSAppearance(named: .aqua) : nil
            window.contentView = host
            window.setContentSize(size)
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            let fit = host.fittingSize
            if !fit.width.isFinite || !fit.height.isFinite || fit.width > size.width + 1 || fit.height > size.height + 1 {
                failures += 1
                print("Native UI invalid: \(name) fit=\(fit) frame=\(size)")
            }
            if capture, let outputDirectory {
                window.center()
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                RunLoop.current.run(until: Date().addingTimeInterval(0.08))
                host.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                host.displayIfNeeded()
                if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let data = bitmap.representation(using: .png, properties: [:]) {
                        do { try data.write(to: outputDirectory.appendingPathComponent(name + ".png")) }
                        catch { failures += 1; print("Native UI capture failed: \(name)") }
                    } else { failures += 1 }
                } else { failures += 1 }
            }
            if window === captureWindow { window.orderOut(nil) }
            else { window.close() }
        }

        for providerMode in 0..<4 {
            for status in statuses {
                let hasClaude = providerMode == 1 || providerMode == 3
                let hasCodex = providerMode == 2 || providerMode == 3
                let retainsValue = status == .ready || status == .offline || status == .error || status == .rateLimited
                let state = ApplicationState(
                    claudeStatus: hasClaude ? status : .unavailable,
                    claudeMessage: providerMessage("Claude", status: hasClaude ? status : .unavailable),
                    claudeSnapshot: hasClaude && retainsValue ? claude : nil,
                    codexStatus: hasCodex ? status : .unavailable,
                    codexMessage: providerMessage("Codex", status: hasCodex ? status : .unavailable),
                    codexSnapshot: hasCodex && retainsValue ? codex : nil,
                    updatedAt: timestamp,
                    retryAt: status == .rateLimited ? timestamp.addingTimeInterval(60) : nil
                )
                for appearance in appearances {
                    var settings = AppSettings()
                    settings.appearance = appearance
                    let model = AppModel(previewState: state, previewSettings: settings)
                    render(UsageDetailsView(model: model, onOpenSettings: {}), size: NSSize(width: 430, height: 560), appearance: appearance, locale: "ko", name: "details-\(providerMode)-\(status.rawValue)-\(appearance.rawValue)", capture: providerMode == 3 && (status == .ready || status == .rateLimited) && appearance != .system)
                    detailCount += 1
                }
            }
        }

        let previewState = ApplicationState(claudeStatus: .ready, claudeSnapshot: claude, codexStatus: .ready, codexSnapshot: codex, updatedAt: timestamp)
        let model = AppModel(previewState: previewState)
        let isolatedDefaults = UserDefaults(suiteName: "dev.taemtaem.dejavu.validation.\(UUID().uuidString)")!
        for pane in ["Widget", "Appearance", "Providers", "General", "Updates", "Privacy"] {
            for appearance in appearances {
                for locale in ["ko", "en"] {
                    for size in [NSSize(width: 700, height: 500), NSSize(width: 780, height: 580)] {
                        render(SettingsView(model: model, updateCoordinator: UpdateCoordinator(), onShowOnboarding: {}, previewPane: pane).defaultAppStorage(isolatedDefaults), size: size, appearance: appearance, locale: locale, name: "settings-\(pane)-\(locale)-\(appearance.rawValue)-\(Int(size.width))", capture: locale == "ko" && appearance == .light && size.width == 780)
                        settingsCount += 1
                    }
                }
            }
        }
        var previousSignInSettings = AppSettings()
        previousSignInSettings.claudeCredentialIdentity = .previousDejavuDefault
        let previousSignInModel = AppModel(previewState: previewState, previewSettings: previousSignInSettings)
        for appearance in appearances {
            for locale in ["ko", "en"] {
                for size in [NSSize(width: 700, height: 500), NSSize(width: 780, height: 580)] {
                    render(SettingsView(model: previousSignInModel, updateCoordinator: UpdateCoordinator(), onShowOnboarding: {}, previewPane: "Providers", previewScrollTarget: "claude-sign-in-location").defaultAppStorage(isolatedDefaults), size: size, appearance: appearance, locale: locale, name: "settings-providers-previous-sign-in-\(locale)-\(appearance.rawValue)-\(Int(size.width))", capture: locale == "ko" && appearance == .light && size.width == 780)
                    settingsCount += 1
                }
            }
        }
        for page in 0..<3 {
            for appearance in appearances {
                for locale in ["ko", "en"] {
                    render(OnboardingView(model: model, onFinish: {}, initialPage: page), size: NSSize(width: 660, height: 620), appearance: appearance, locale: locale, name: "onboarding-\(page)-\(locale)-\(appearance.rawValue)", capture: locale == "ko" && appearance == .light)
                    onboardingCount += 1
                }
            }
        }
        for providerMode in 0..<4 {
            for density in WidgetDensity.allCases {
                for rowLayout in WidgetLayout.allCases {
                    for progress in [false, true] {
                        for fable in [false, true] {
                            for appearance in appearances {
                                var settings = AppSettings()
                                settings.widgetDensity = density
                                settings.widgetLayout = rowLayout
                                settings.showProgress = progress
                                settings.extendedFableAccessEnabled = fable
                                settings.appearance = appearance
                                let hasClaude = providerMode == 1 || providerMode == 3
                                let hasCodex = providerMode == 2 || providerMode == 3
                                let widgetClaude = ClaudeUsageSnapshot(fiveHour: claude.fiveHour, weekly: claude.weekly, fable: fable ? claude.fable : nil, capturedAt: timestamp)
                                let state = ApplicationState(claudeStatus: hasClaude ? .ready : .unavailable, claudeSnapshot: hasClaude ? widgetClaude : nil, codexStatus: hasCodex ? .ready : .unavailable, codexSnapshot: hasCodex ? codex : nil)
                                let widgetModel = AppModel(previewState: state, previewSettings: settings)
                                let layout = WidgetPanelController.layout(for: widgetModel)
                                render(ModernWidgetView(model: widgetModel, layout: layout, measuresNaturalSize: true, onOpenDetails: {}), size: NSSize(width: layout.panelWidth, height: layout.panelHeight), appearance: appearance, locale: "ko", name: "floating-\(providerMode)-\(density.rawValue)-\(rowLayout.rawValue)-\(progress)-\(fable)-\(appearance.rawValue)", capture: providerMode == 3 && density == .compact && rowLayout == .singleRow && progress && fable && appearance == .light)
                                floatingCount += 1
                            }
                        }
                    }
                }
            }
        }
        print("Native UI matrix: \(detailCount) details, \(settingsCount) settings, \(onboardingCount) onboarding, \(floatingCount) floating, \(failures) invalid")
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--ui-validation-hold=") }),
           let seconds = Double(argument.dropFirst("--ui-validation-hold=".count)),
           seconds.isFinite, seconds > 0 {
            // Explicit, bounded synthetic-only preview for inspecting native
            // compositor output that cacheDisplay cannot reliably represent.
            let preview = SettingsView(model: model, updateCoordinator: UpdateCoordinator(), onShowOnboarding: {}, previewPane: "Providers")
                .defaultAppStorage(isolatedDefaults)
                .environment(\.locale, Locale(identifier: "ko"))
                .preferredColorScheme(.light)
            captureWindow.appearance = NSAppearance(named: .aqua)
            captureWindow.contentView = NSHostingView(rootView: preview)
            captureWindow.setContentSize(NSSize(width: 780, height: 580))
            captureWindow.center()
            NSApp.activate()
            captureWindow.makeKeyAndOrderFront(nil)
            captureWindow.contentView?.layoutSubtreeIfNeeded()
            captureWindow.displayIfNeeded()
            print("Synthetic UI preview: holding Connections for \(min(60, seconds)) seconds")
            RunLoop.current.run(until: Date().addingTimeInterval(min(60, seconds)))
        }
        captureWindow.close()
        return failures == 0
    }
}
