import AppKit
import Combine
import DejavuDomain
import SwiftUI

private final class NonactivatingWidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WidgetPanelController: NSObject, NSWindowDelegate {
    var onOpenDetails: () -> Void = {}

    private static let edgeMargin: CGFloat = 12

    private let model: AppModel
    private let panel: NonactivatingWidgetPanel
    private var isApplyingPlacement = false
    private var hasAppliedInitialPlacement = false
    private var lastLayout: WidgetLayoutMetrics?
    private var lastPlacement: WidgetPlacement?
    private var lastCustomPosition: WidgetPosition?
    private var modelObservation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        let initialLayout = Self.layout(for: model)
        panel = NonactivatingWidgetPanel(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: initialLayout.panelWidth, height: initialLayout.panelHeight)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        configurePanel()
        applyContent(layout: initialLayout)
        modelObservation = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    // objectWillChange is emitted before the published value is
                    // committed, so update on the next main-actor turn.
                    await Task.yield()
                    self?.modelDidChange()
                }
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        if !hasAppliedInitialPlacement {
            applyConfiguredPlacement()
            hasAppliedInitialPlacement = true
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func close() {
        modelObservation?.cancel()
        modelObservation = nil
        NotificationCenter.default.removeObserver(self)
        panel.orderOut(nil)
        panel.close()
    }

    func windowDidMove(_ notification: Notification) {
        guard hasAppliedInitialPlacement, !isApplyingPlacement else { return }
        model.rememberWidgetPosition(
            displayIdentifier: Self.displayIdentifier(for: panel.screen),
            topLeftX: panel.frame.minX,
            topLeftY: panel.frame.maxY
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        applyConfiguredPlacement()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.isRestorable = false
    }

    private func modelDidChange() {
        let nextLayout = Self.layout(for: model)
        let layoutChanged = nextLayout != lastLayout
        let placementChanged = model.widgetPlacement != lastPlacement
        let customPositionChanged = model.customWidgetPosition != lastCustomPosition
        let oldTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        if layoutChanged {
            applyContent(layout: nextLayout)
            let nextSize = NSSize(width: nextLayout.panelWidth, height: nextLayout.panelHeight)
            panel.setContentSize(nextSize)
        }

        switch model.widgetPlacement {
        case .topRight:
            if layoutChanged || placementChanged {
                applyTopRightPlacement()
            }
        case .bottomRight:
            if layoutChanged || placementChanged {
                applyBottomRightPlacement()
            }
        case .custom:
            if placementChanged || customPositionChanged {
                applyStoredCustomPlacement()
            } else if layoutChanged {
                isApplyingPlacement = true
                panel.setFrame(
                    NSRect(
                        x: oldTopLeft.x,
                        y: oldTopLeft.y - panel.frame.height,
                        width: panel.frame.width,
                        height: panel.frame.height
                    ),
                    display: true
                )
                isApplyingPlacement = false
                clampToVisibleScreen()
            }
        }

        lastPlacement = model.widgetPlacement
        lastCustomPosition = model.customWidgetPosition
    }

    private func applyConfiguredPlacement() {
        switch model.widgetPlacement {
        case .topRight:
            applyTopRightPlacement()
        case .bottomRight:
            applyBottomRightPlacement()
        case .custom:
            applyStoredCustomPlacement()
        }
        lastPlacement = model.widgetPlacement
        lastCustomPosition = model.customWidgetPosition
    }

    private func applyContent(layout: WidgetLayoutMetrics) {
        lastLayout = layout
        panel.contentView = NSHostingView(
            rootView: ModernWidgetView(
                model: model,
                layout: layout,
                onOpenDetails: { [weak self] in self?.onOpenDetails() }
            )
        )
    }

    private func applyTopRightPlacement() {
        guard let screen = preferredScreen() else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - Self.edgeMargin,
            y: frame.maxY - panel.frame.height - Self.edgeMargin
        )
        setFrameOrigin(origin)
    }

    private func applyBottomRightPlacement() {
        guard let screen = preferredScreen() else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - Self.edgeMargin,
            y: frame.minY + Self.edgeMargin
        )
        setFrameOrigin(origin)
    }

    private func applyStoredCustomPlacement() {
        guard let position = model.customWidgetPosition else {
            applyTopRightPlacement()
            return
        }
        let screen = preferredScreen(displayIdentifier: position.displayIdentifier)
        isApplyingPlacement = true
        panel.setFrameOrigin(
            NSPoint(
                x: position.topLeftX,
                y: position.topLeftY - panel.frame.height
            )
        )
        isApplyingPlacement = false
        clampToVisibleScreen(screen)
    }

    private func clampToVisibleScreen(_ requestedScreen: NSScreen? = nil) {
        guard let screen = requestedScreen ?? preferredScreen() else { return }
        let visibleFrame = screen.visibleFrame
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - panel.frame.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - panel.frame.height)
        let origin = NSPoint(
            x: min(max(panel.frame.minX, visibleFrame.minX), maximumX),
            y: min(max(panel.frame.minY, visibleFrame.minY), maximumY)
        )
        setFrameOrigin(origin)
    }

    private func preferredScreen(displayIdentifier: String? = nil) -> NSScreen? {
        if let displayIdentifier,
           let matched = NSScreen.screens.first(where: {
               Self.displayIdentifier(for: $0) == displayIdentifier
           }) {
            return matched
        }
        return panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func displayIdentifier(for screen: NSScreen?) -> String? {
        guard let number = screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else {
            return nil
        }
        return number.stringValue
    }

    private func setFrameOrigin(_ origin: NSPoint) {
        isApplyingPlacement = true
        panel.setFrameOrigin(origin)
        isApplyingPlacement = false
    }

    private static func layout(for model: AppModel) -> WidgetLayoutMetrics {
        let providers = model.visibleProviders
        let claude = providers.first { $0.kind == .claude }
        let hasFableValue = claude?.limits.first {
            $0.id == "claude-fable"
        }?.displayPercent != nil

        return WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: model.widgetDensity,
                requestedLayout: model.widgetLayout,
                showClaude: providers.contains { $0.kind == .claude },
                showCodex: providers.contains { $0.kind == .codex },
                showProgress: model.showProgress,
                claudeMetricSlots: model.extendedFableAccessEnabled || hasFableValue ? 3 : 2,
                appearance: model.appearance,
                accessibilityTextScale: 1
            )
        )
    }
}
