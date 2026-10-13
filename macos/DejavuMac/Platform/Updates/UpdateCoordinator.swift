import AppKit
import Combine
import DejavuDomain
import Foundation
import Sparkle

@MainActor
final class UpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate {
    enum Status: Equatable {
        case ready
        case checking
        case available(version: String)
        case current
        case failed
        case configurationRequired

        var message: String {
            switch self {
            case .ready:
                NSLocalizedString(
                    "Updates are checked securely with Sparkle.",
                    comment: "Updater ready status"
                )
            case .checking:
                NSLocalizedString("Checking for updates…", comment: "Updater checking status")
            case let .available(version):
                String(
                    format: NSLocalizedString(
                        "Dejavu %@ is available.",
                        comment: "Updater available status; argument is the version"
                    ),
                    version
                )
            case .current:
                NSLocalizedString("You’re up to date.", comment: "Updater current status")
            case .failed:
                NSLocalizedString(
                    "Couldn’t check for updates. Try again later.",
                    comment: "Updater failure status"
                )
            case .configurationRequired:
                NSLocalizedString(
                    "Update signing must be configured for this build.",
                    comment: "Unsigned development build update status"
                )
            }
        }
    }

    var onRememberNotifiedVersion: (String) -> Void = { _ in }

    @Published private(set) var status: Status = .ready
    @Published private(set) var canCheckForUpdates = false

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var canCheckObservation: NSKeyValueObservation?
    private var automaticCheckTask: Task<Void, Never>?
    private var checkState = UpdateCheckState()
    private var lastNotifiedVersion: String?
    private var nextAutomaticCheckAt: Date?
    private var automaticChecksEnabled = false
    private var isManualCycle = false
    private var isStarted = false

    override init() {
        super.init()
    }

    func start(
        automaticallyChecksForUpdates: Bool,
        lastNotifiedVersion: String?
    ) {
        if isStarted {
            setAutomaticallyChecksForUpdates(automaticallyChecksForUpdates)
            return
        }

        guard Self.hasSecureUpdateConfiguration else {
            status = .configurationRequired
            return
        }

        isStarted = true
        automaticChecksEnabled = automaticallyChecksForUpdates
        self.lastNotifiedVersion = lastNotifiedVersion
        updaterController.startUpdater()

        // Dejavu owns the wall-clock schedule so it matches the Windows app.
        // Sparkle still owns download, verification, installation, and relaunch.
        updaterController.updater.automaticallyChecksForUpdates = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockOrWakeDidChange(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemClockOrWakeDidChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemClockOrWakeDidChange(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        canCheckObservation = updaterController.updater.observe(\.canCheckForUpdates, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Re-read after the actor hop: rapid Sparkle changes must not apply
                // an older queued observation after its actual state has changed.
                self.canCheckForUpdates = self.updaterController.updater.canCheckForUpdates
            }
        }
        scheduleAutomaticChecks(includeStartupCheck: true)
    }

    func stop() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        nextAutomaticCheckAt = nil
        canCheckObservation?.invalidate()
        canCheckObservation = nil
        NotificationCenter.default.removeObserver(self, name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSSystemTimeZoneDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func checkForUpdates() {
        guard isStarted, canCheckForUpdates else { return }
        isManualCycle = true
        checkState.beginCheck(manual: true)
        applyCheckPresentation()
        NSApp.activate()
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticChecksEnabled = enabled
        guard isStarted else { return }
        scheduleAutomaticChecks(includeStartupCheck: enabled)
    }

    func applicationDidBecomeActive(automaticallyChecksForUpdates: Bool) {
        guard isStarted, automaticallyChecksForUpdates else { return }
        automaticChecksEnabled = true
        // A nil deadline means the four-second startup check is still pending.
        // Do not cancel it merely because the accessory app became active.
        guard let deadline = nextAutomaticCheckAt else { return }
        if Date() >= deadline {
            performBackgroundCheckIfPossible()
        }
        scheduleAutomaticChecks(includeStartupCheck: false)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard isManualCycle || automaticChecksEnabled else { return }
        let version = item.displayVersionString
        checkState.foundUpdate(version: version)
        applyCheckPresentation()

        guard automaticChecksEnabled,
              !isManualCycle,
              AutomaticUpdatePolicy.shouldNotify(
                availableVersion: version,
                lastNotifiedVersion: lastNotifiedVersion
              ) else { return }

        lastNotifiedVersion = version
        onRememberNotifiedVersion(version)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        checkState.finish(outcome: .noUpdate, manual: isManualCycle)
        applyCheckPresentation()
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        defer { isManualCycle = false }

        if let error {
            let cocoaError = error as NSError
            let isNoUpdate = cocoaError.domain == SUSparkleErrorDomain && cocoaError.code == 1001
            checkState.finish(outcome: isNoUpdate ? .noUpdate : .failed, manual: isManualCycle)
        } else {
            checkState.finish(outcome: .completed, manual: isManualCycle)
        }
        applyCheckPresentation()
    }

    private func scheduleAutomaticChecks(includeStartupCheck: Bool) {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
        nextAutomaticCheckAt = nil
        guard isStarted, automaticChecksEnabled else { return }

        automaticCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }

            if includeStartupCheck {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                guard automaticChecksEnabled else { return }
                performBackgroundCheckIfPossible()
            }

            while automaticChecksEnabled, !Task.isCancelled {
                let next = HourlyUpdateSchedule.nextCheckAt(after: Date())
                nextAutomaticCheckAt = next
                do {
                    try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                } catch {
                    return
                }
                guard automaticChecksEnabled else { return }
                performBackgroundCheckIfPossible()
            }
        }
    }

    private func performBackgroundCheckIfPossible() {
        guard automaticChecksEnabled, updaterController.updater.canCheckForUpdates else { return }
        isManualCycle = false
        checkState.beginCheck(manual: false)
        updaterController.updater.checkForUpdatesInBackground()
    }

    private func applyCheckPresentation() {
        switch checkState.presentation {
        case .ready: status = .ready
        case .checking: status = .checking
        case let .available(version): status = .available(version: version)
        case .current: status = .current
        case .failed: status = .failed
        }
    }

    @objc private func systemClockOrWakeDidChange(_ notification: Notification) {
        applicationDidBecomeActive(automaticallyChecksForUpdates: automaticChecksEnabled)
    }

    private static var hasSecureUpdateConfiguration: Bool {
        let bundle = Bundle.main
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let feedString = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let feedURL = URL(string: feedString),
              feedURL.scheme?.lowercased() == "https" else {
            return false
        }
        return true
    }
}
