import DejavuDomain
import SwiftUI

extension Color {
    init?(dejavuHex value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "#" else { return nil }

        let digits = String(trimmed.dropFirst())
        guard digits.count == 6 || digits.count == 8,
              let rawValue = UInt64(digits, radix: 16) else { return nil }

        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
        if digits.count == 8 {
            red = Double((rawValue >> 24) & 0xFF) / 255
            green = Double((rawValue >> 16) & 0xFF) / 255
            blue = Double((rawValue >> 8) & 0xFF) / 255
            opacity = Double(rawValue & 0xFF) / 255
        } else {
            red = Double((rawValue >> 16) & 0xFF) / 255
            green = Double((rawValue >> 8) & 0xFF) / 255
            blue = Double(rawValue & 0xFF) / 255
            opacity = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension UsageColorLevel {
    var color: Color {
        switch self {
        case .normal:
            .primary
        case .warning:
            .orange
        case .danger:
            .red
        }
    }
}

func usageColor(
    for displayPercent: Double?,
    enabled: Bool = true,
    normalColor: Color = .primary
) -> Color {
    guard enabled else { return normalColor }
    switch UsageColorLevel.level(for: displayPercent) {
    case .normal:
        return normalColor
    case .warning:
        return .orange
    case .danger:
        return .red
    }
}

/// Progress bars keep the native accent color in the normal range, then use
/// the same warning and danger thresholds as their percentage label.
func usageProgressColor(
    for displayPercent: Double?,
    enabled: Bool = true,
    normalColor: Color = .accentColor
) -> Color {
    guard enabled else { return normalColor }
    switch UsageColorLevel.level(for: displayPercent) {
    case .normal:
        return normalColor
    case .warning:
        return .orange
    case .danger:
        return .red
    }
}
