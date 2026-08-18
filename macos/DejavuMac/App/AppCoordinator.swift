import AppKit
import Combine
import DejavuDomain
import SwiftUI

@MainActor
final class AppCoordinator: NSObject {
    private let model: AppModel
    let updateCoordinator: UpdateCoordinator
    private let statusItemController: StatusItemController
    private let widgetPanelController: WidgetPanelController

    private var detailsWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?
    private var widgetVisibilityObservation: AnyCancellable?
    private var updateSettingObservation: AnyCancellable?
    private var appearanceObservation: AnyCancellable?
    private var isStopped = false

    var automaticUpdateChecksEnabled: Bool { model.automaticUpdateChecksEnabled }

    init(model: AppModel) {
        self.model = model
        updateCoordinator = UpdateCoordinator()
        statusItemController = StatusItemController(model: model, updateCoordinator: updateCoordinator)
        widgetPanelController = WidgetPanelController(model: model)
        super.init()

        updateCoordinator.onRememberNotifiedVersion = { [weak model] version in
            model?.rememberNotifiedUpdateVersion(version)
        }

        statusItemController.onShowDetails = { [weak self] in self?.showDetails() }
        statusItemController.onShowSettings = { [weak self] in self?.showSettings() }
        statusItemController.onRefresh = { [weak self] in self?.model.refresh(force: true) }
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
        detailsWindowController?.window?.close()
        settingsWindowController?.window?.close()
        onboardingWindowController?.window?.close()
    }

    func showDetails() {
        if detailsWindowController == nil {
            let rootView = UsageDetailsView(
                model: model,
                onOpenSettings: { [weak self] in self?.showSettings() }
            )
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            configureAuxiliaryWindow(panel, title: "Dejavu Usage")
            panel.isFloatingPanel = true
            panel.contentViewController = NSHostingController(rootView: rootView)
            detailsWindowController = NSWindowController(window: panel)
        }
        present(detailsWindowController)
    }

    func showSettings() {
        if settingsWindowController == nil {
            let rootView = SettingsView(
                model: model,
                updateCoordinator: updateCoordinator,
                onShowOnboarding: { [weak self] in self?.showOnboarding() }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            configureAuxiliaryWindow(window, title: "Dejavu Settings")
            window.minSize = NSSize(width: 700, height: 500)
            window.contentViewController = NSHostingController(rootView: rootView)
            settingsWindowController = NSWindowController(window: window)
        }
        present(settingsWindowController)
    }

    func showOnboarding() {
        if onboardingWindowController == nil {
            let rootView = OnboardingView(onFinish: { [weak self] in
                self?.onboardingWindowController?.window?.orderOut(nil)
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            configureAuxiliaryWindow(window, title: "Welcome to Dejavu")
            window.contentViewController = NSHostingController(rootView: rootView)
            onboardingWindowController = NSWindowController(window: window)
        }
        present(onboardingWindowController)
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
        window.title = title
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
