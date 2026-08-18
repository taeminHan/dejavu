import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var pendingOpenURLs = [URL]()
    private var isPreparingForTermination = false
    private var exitsForExistingInstance = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let existing = NSRunningApplication.runningApplications(
                  withBundleIdentifier: bundleIdentifier
              ).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
        else { return }

        exitsForExistingInstance = true
        DistributedNotificationCenter.default().postNotificationName(
            .dejavuActivateExisting,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        existing.activate(options: [.activateAllWindows])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !exitsForExistingInstance else {
            NSApp.terminate(nil)
            return
        }
        let coordinator = AppCoordinator(model: AppModel())
        self.coordinator = coordinator
        coordinator.start(arguments: ProcessInfo.processInfo.arguments)
        openPendingURLs(with: coordinator)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreparingForTermination else { return .terminateLater }
        isPreparingForTermination = true

        Task { @MainActor [weak self] in
            await self?.coordinator?.prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator?.showSettings()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let coordinator else { return }
        coordinator.updateCoordinator.applicationDidBecomeActive(
            automaticallyChecksForUpdates: coordinator.automaticUpdateChecksEnabled
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }

        for url in urls {
            _ = coordinator.handleOpenURL(url)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
        coordinator = nil
    }

    private func openPendingURLs(with coordinator: AppCoordinator) {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        for url in urls {
            _ = coordinator.handleOpenURL(url)
        }
    }
}
