import Foundation

public struct WidgetSize: Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct WidgetLayoutRequest: Hashable, Sendable {
    public let density: WidgetDensity
    public let requestedLayout: WidgetLayout
    public let showClaude: Bool
    public let showCodex: Bool
    public let showProgress: Bool
    public let claudeMetricSlots: Int
    public let codexMetricSlots: Int
    public let appearance: ThemePreference
    public let accessibilityTextScale: Double

    public init(
        density: WidgetDensity,
        requestedLayout: WidgetLayout,
        showClaude: Bool,
        showCodex: Bool,
        showProgress: Bool,
        claudeMetricSlots: Int = 2,
        codexMetricSlots: Int = 2,
        appearance: ThemePreference = .system,
        accessibilityTextScale: Double = 1
    ) {
        self.density = density
        self.requestedLayout = requestedLayout
        self.showClaude = showClaude
        self.showCodex = showCodex
        self.showProgress = showProgress
        self.claudeMetricSlots = claudeMetricSlots
        self.codexMetricSlots = codexMetricSlots
        self.appearance = appearance
        self.accessibilityTextScale = accessibilityTextScale
    }

    public init(
        density: WidgetDensity,
        requestedLayout: WidgetLayout,
        serviceState: WidgetServiceState,
        showProgress: Bool,
        appearance: ThemePreference = .system,
        accessibilityTextScale: Double = 1
    ) {
        let visibility = serviceState.visibility
        self.init(
            density: density,
            requestedLayout: requestedLayout,
            showClaude: visibility.showClaude,
            showCodex: visibility.showCodex,
            showProgress: showProgress,
            appearance: appearance,
            accessibilityTextScale: accessibilityTextScale
        )
    }
}

public struct WidgetLayoutMetrics: Hashable, Sendable {
    public let panelSize: WidgetSize
    public let effectiveLayout: WidgetLayout
    public let providerOrder: [UsageProviderID]
    public let providerGap: Double
    public let metricGap: Double
    public let progressFootprint: Double
    public let metricCellWidth: Double
    public let claudeContentWidth: Double
    public let codexContentWidth: Double
    public let smallRingDiameter: Double
    public let contentPadding: Double

    public init(
        panelSize: WidgetSize,
        effectiveLayout: WidgetLayout,
        providerOrder: [UsageProviderID],
        providerGap: Double,
        metricGap: Double,
        progressFootprint: Double,
        metricCellWidth: Double,
        claudeContentWidth: Double,
        codexContentWidth: Double,
        smallRingDiameter: Double,
        contentPadding: Double
    ) {
        self.panelSize = panelSize
        self.effectiveLayout = effectiveLayout
        self.providerOrder = providerOrder
        self.providerGap = providerGap
        self.metricGap = metricGap
        self.progressFootprint = progressFootprint
        self.metricCellWidth = metricCellWidth
        self.claudeContentWidth = claudeContentWidth
        self.codexContentWidth = codexContentWidth
        self.smallRingDiameter = smallRingDiameter
        self.contentPadding = contentPadding
    }

    public var panelWidth: Double { panelSize.width }
    public var panelHeight: Double { panelSize.height }

    public func providerContentWidth(for provider: UsageProviderID) -> Double {
        switch provider {
        case .claude:
            claudeContentWidth
        case .codex:
            codexContentWidth
        }
    }
}

/// AppKit/SwiftUI-free geometry source for every widget service state.
public enum WidgetLayoutCalculator {
    public static func calculate(_ request: WidgetLayoutRequest) -> WidgetLayoutMetrics {
        let providerCount = (request.showClaude ? 1 : 0) + (request.showCodex ? 1 : 0)
        let effectiveLayout: WidgetLayout = request.requestedLayout == .twoRows && providerCount == 2
            ? .twoRows
            : .singleRow
        let scale = normalizedTextScale(request.accessibilityTextScale)

        let baseMetricCellWidth: Double
        let metricGap: Double
        let padding: Double
        let providerGap: Double
        let rowWithoutProgress: Double
        let progressFootprint: Double

        switch request.density {
        case .small:
            baseMetricCellWidth = 48
            metricGap = 6
            padding = 10
            providerGap = providerCount == 2 ? 8 : 0
            rowWithoutProgress = max(48, ceil(40 * scale))
            progressFootprint = 0
        case .compact:
            baseMetricCellWidth = 72
            metricGap = 10
            padding = 12
            providerGap = providerCount == 2 ? 10 : 0
            rowWithoutProgress = ceil(35 * scale)
            progressFootprint = request.showProgress ? 9 : 0
        case .comfortable:
            baseMetricCellWidth = 88
            metricGap = 14
            padding = 14
            providerGap = providerCount == 2 ? 12 : 0
            rowWithoutProgress = ceil(42 * scale)
            progressFootprint = request.showProgress ? 11 : 0
        }

        let metricCellWidth = ceil(baseMetricCellWidth * scale)
        let claudeContentWidth = providerWidth(
            metricCellWidth: metricCellWidth,
            metricGap: metricGap,
            slots: request.claudeMetricSlots
        )
        let codexContentWidth = providerWidth(
            metricCellWidth: metricCellWidth,
            metricGap: metricGap,
            slots: request.codexMetricSlots
        )
        let rowHeight = rowWithoutProgress + progressFootprint
        let size: WidgetSize

        if providerCount == 0 {
            let emptyWidth: Double
            let emptyHeight: Double
            switch request.density {
            case .small:
                emptyWidth = 250
                emptyHeight = 34
            case .compact:
                emptyWidth = 300
                emptyHeight = 40
            case .comfortable:
                emptyWidth = 360
                emptyHeight = 48
            }
            size = WidgetSize(width: ceil(emptyWidth * scale), height: ceil(emptyHeight * scale))
        } else if effectiveLayout == .singleRow {
            let contentWidth = (request.showClaude ? claudeContentWidth : 0)
                + (request.showCodex ? codexContentWidth : 0)
                + providerGap
            size = WidgetSize(
                width: ceil(contentWidth + padding * 2),
                height: ceil(rowHeight + padding * 2)
            )
        } else {
            size = WidgetSize(
                width: ceil(max(claudeContentWidth, codexContentWidth) + padding * 2),
                height: ceil(rowHeight * 2 + providerGap + padding * 2)
            )
        }

        let providerOrder: [UsageProviderID]
        if effectiveLayout == .twoRows {
            providerOrder = [.codex, .claude]
        } else {
            providerOrder = [
                request.showClaude ? .claude : nil,
                request.showCodex ? .codex : nil
            ].compactMap { $0 }
        }

        return WidgetLayoutMetrics(
            panelSize: size,
            effectiveLayout: effectiveLayout,
            providerOrder: providerOrder,
            providerGap: providerGap,
            metricGap: metricGap,
            progressFootprint: progressFootprint,
            metricCellWidth: metricCellWidth,
            claudeContentWidth: claudeContentWidth,
            codexContentWidth: codexContentWidth,
            smallRingDiameter: 30,
            contentPadding: padding
        )
    }

    private static func normalizedTextScale(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(2, max(1, value))
    }

    private static func providerWidth(
        metricCellWidth: Double,
        metricGap: Double,
        slots: Int
    ) -> Double {
        let normalizedSlots = min(3, max(1, slots))
        return metricCellWidth * Double(normalizedSlots)
            + metricGap * Double(normalizedSlots - 1)
    }
}
