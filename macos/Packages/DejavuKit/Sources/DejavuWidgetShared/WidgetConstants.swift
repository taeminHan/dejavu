import Foundation

public enum WidgetConstants {
    /// This value is also exposed as `DEJAVU_APP_GROUP_IDENTIFIER` in the Xcode
    /// project so a signed build can replace it without changing the storage API.
    public static let defaultAppGroupIdentifier = "group.dev.taemtaem.dejavu"
    public static let appGroupInfoDictionaryKey = "DEJAVUAppGroupIdentifier"
    public static let usageKind = "dev.taemtaem.dejavu.usage"
    public static let snapshotFilename = "widget-usage.json"
    public static let maximumSnapshotBytes = 64 * 1_024
    public static let timelineFallbackInterval: TimeInterval = 30 * 60
    public static let snapshotMaximumAge: TimeInterval = 30 * 60

    public static func appGroupIdentifier(in bundle: Bundle = .main) -> String {
        guard let configured = bundle.object(
            forInfoDictionaryKey: appGroupInfoDictionaryKey
        ) as? String else {
            return defaultAppGroupIdentifier
        }
        let trimmed = configured.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultAppGroupIdentifier : trimmed
    }
}
