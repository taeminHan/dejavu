import Foundation

// Offline transport shim for compiling the ACTUAL UpdateCoordinator in a
// deterministic native KVO test. This is never linked into the shipped app.
// It does not simulate or establish Sparkle download/signature/install behavior.
public let SUSparkleErrorDomain = "SUSparkleErrorDomain"
public enum SPUUpdateCheck { case updates }
@MainActor public protocol SPUUpdaterDelegate: AnyObject {}

@MainActor
public final class SUAppcastItem: NSObject {
    public let displayVersionString: String
    public init(displayVersionString: String) { self.displayVersionString = displayVersionString }
}

@MainActor
public final class SPUUpdater: NSObject {
    @objc dynamic public var canCheckForUpdates = false
    public var automaticallyChecksForUpdates = false
    public private(set) var manualRequests = 0
    public private(set) var backgroundRequests = 0

    public func checkForUpdatesInBackground() { backgroundRequests += 1 }
    public func checkManually() { manualRequests += 1 }
}

@MainActor
public final class SPUStandardUpdaterController: NSObject {
    public static var latest: SPUStandardUpdaterController?
    public let updater = SPUUpdater()

    public init(startingUpdater: Bool, updaterDelegate: (any SPUUpdaterDelegate)?, userDriverDelegate: AnyObject?) {
        super.init()
        Self.latest = self
        if startingUpdater { startUpdater() }
    }

    public func startUpdater() { updater.canCheckForUpdates = true }
    public func checkForUpdates(_ sender: Any?) { updater.checkManually() }
}
