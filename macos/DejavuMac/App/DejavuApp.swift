import SwiftUI

@main
struct DejavuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .dejavuOpenSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let dejavuOpenSettings = Notification.Name("dev.dejavu.open-settings")
    static let dejavuActivateExisting = Notification.Name(
        "dev.taemtaem.dejavu.activate-existing"
    )
}
