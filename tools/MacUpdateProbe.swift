import AppKit
import Foundation
import Sparkle

@main
@MainActor
struct MacUpdateProbe {
    private static var checked = 0

    static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let coordinator = UpdateCoordinator()
        coordinator.start(automaticallyChecksForUpdates: false, lastNotifiedVersion: nil)
        defer { coordinator.stop() }
        guard let controller = SPUStandardUpdaterController.latest else {
            throw Failure(message: "The actual coordinator did not start its injected updater.")
        }
        try check(coordinator.canCheckForUpdates, "Initial updater availability must reach the button binding.")
        controller.updater.canCheckForUpdates = false
        try await wait { !coordinator.canCheckForUpdates }
        try check(!coordinator.canCheckForUpdates, "A busy updater must disable the check button.")
        controller.updater.canCheckForUpdates = true
        try await wait { coordinator.canCheckForUpdates }
        try check(coordinator.canCheckForUpdates, "KVO must re-enable the check button when the updater becomes available.")

        coordinator.checkForUpdates()
        try check(coordinator.status == .checking && controller.updater.manualRequests == 1, "A manual check must update presentation and dispatch exactly once.")
        let item = SUAppcastItem(displayVersionString: "0.9.6")
        coordinator.updater(controller.updater, didFindValidUpdate: item)
        coordinator.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: nil)
        try check(coordinator.status == .available(version: "0.9.6"), "A found release must be retained after the cycle finishes.")

        coordinator.checkForUpdates()
        coordinator.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        try check(coordinator.status == .available(version: "0.9.6"), "A subsequent failed check must not withdraw the discovered release.")
        coordinator.checkForUpdates()
        let current = NSError(domain: SUSparkleErrorDomain, code: 1001)
        coordinator.updaterDidNotFindUpdate(controller.updater, error: current)
        coordinator.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: current)
        try check(coordinator.status == .current, "Only a definitive no-update result clears the discovered release.")

        coordinator.checkForUpdates()
        coordinator.updater(controller.updater, didFinishUpdateCycleFor: .updates, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        try check(coordinator.status == .failed, "A manual failure without a discovered release must be visible.")
        try check(!controller.updater.automaticallyChecksForUpdates, "Dejavu must retain ownership of automatic scheduling.")
        try check(controller.updater.backgroundRequests == 0, "Disabled automatic checks must not start a background request.")
        print("Native UpdateCoordinator regressions: \(checked) checked, 0 failed (actual coordinator, Foundation KVO, offline Sparkle transport shim).")
    }

    private static func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure(message: "Timed out waiting for the actual coordinator's KVO binding.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        checked += 1
        if !condition { throw Failure(message: message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
