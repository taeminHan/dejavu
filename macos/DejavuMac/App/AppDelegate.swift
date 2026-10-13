import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var pendingOpenURLs = [URL]()
    private var isPreparingForTermination = false
    private var exitsForExistingInstance = false
    private var instanceLockDescriptor: Int32 = -1

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains("--validate-ui") { return }
        // Hold an atomic, user-owned lock for the process lifetime. The
        // running-application lookup below is activation, not mutual exclusion.
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dejavu", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let lockURL = directory.appendingPathComponent(".instance.lock")
            instanceLockDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
            var info = stat()
            guard instanceLockDescriptor >= 0, fstat(instanceLockDescriptor, &info) == 0,
                  info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG else {
                throw CocoaError(.fileReadNoPermission)
            }
            if flock(instanceLockDescriptor, LOCK_EX | LOCK_NB) != 0 { exitsForExistingInstance = true }
        } catch {
            exitsForExistingInstance = true
        }
        guard exitsForExistingInstance else { return }
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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--validate-ui") {
            let output = arguments.first { $0.hasPrefix("--ui-validation-output=") }
                .map { URL(fileURLWithPath: String($0.dropFirst("--ui-validation-output=".count)), isDirectory: true) }
            Darwin.exit(AppCoordinator.runNativeUIValidation(outputDirectory: output) ? 0 : 1)
        }
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
        coordinator.applicationDidBecomeActive()
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
        if instanceLockDescriptor >= 0 {
            _ = flock(instanceLockDescriptor, LOCK_UN)
            _ = Darwin.close(instanceLockDescriptor)
            instanceLockDescriptor = -1
        }
    }

    private func openPendingURLs(with coordinator: AppCoordinator) {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        for url in urls {
            _ = coordinator.handleOpenURL(url)
        }
    }
}
