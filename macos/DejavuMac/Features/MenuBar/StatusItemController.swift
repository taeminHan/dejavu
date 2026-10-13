import AppKit
import Combine
import DejavuDomain

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    var onShowDetails: () -> Void = {}
    var onShowSettings: () -> Void = {}
    var onRefresh: () -> Void = {}
    var onQuit: () -> Void = {}

    private let model: AppModel
    private let updateCoordinator: UpdateCoordinator
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var observations = Set<AnyCancellable>()

    var statusButton: NSStatusBarButton? { statusItem?.button }

    init(model: AppModel, updateCoordinator: UpdateCoordinator) {
        self.model = model
        self.updateCoordinator = updateCoordinator
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    func start() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Dejavu")
        button.imagePosition = .imageLeading
        button.toolTip = NSLocalizedString("Dejavu usage", comment: "Status item tooltip")
        button.setAccessibilityLabel(NSLocalizedString("Dejavu usage", comment: "Status item accessible name"))
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusButton()
        rebuildMenu()

        Publishers.CombineLatest3(
            model.$domainState,
            model.$claudeMenuBarMetrics,
            model.$showsCodexInMenuBar
        )
        .sink { [weak self] domainState, claudeMetrics, showsCodex in
            guard let self else { return }
            let summary = model.statusItemSummary(
                domainState: domainState,
                claudeMetrics: claudeMetrics,
                showsCodex: showsCodex
            )
            updateStatusButton(summary: summary)
        }
        .store(in: &observations)
    }

    func stop() {
        observations.removeAll()
        guard let statusItem else { return }
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let statusItem else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Keep secondary actions in a native context menu. The primary
            // action always opens the attached usage view.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onShowDetails()
        }
    }

    @objc private func showDetails(_ sender: Any?) {
        onShowDetails()
    }

    @objc private func refresh(_ sender: Any?) {
        onRefresh()
    }

    @objc private func showSettings(_ sender: Any?) {
        onShowSettings()
    }

    @objc private func toggleWidget(_ sender: Any?) {
        model.showsWidget.toggle()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateCoordinator.checkForUpdates()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        if model.visibleProviders.isEmpty {
            appendSummary(title: "No provider connected")
        } else {
            for provider in model.visibleProviders {
                appendProviderSummary(provider: provider.kind.brand, limits: provider.limits)
            }
        }

        let updated = model.state.updatedAt?.formatted(date: .omitted, time: .shortened) ?? "--"
        appendSummary(title: String(format: NSLocalizedString("Updated %@", comment: "Last usage check time"), updated))
        menu.addItem(.separator())
        menu.addItem(item(title: "Usage Details", action: #selector(showDetails(_:))))

        let showWidgetItem = item(
            title: NSLocalizedString(
                "Show Floating Overlay",
                comment: "Menu item that toggles the optional NSPanel overlay"
            ),
            action: #selector(toggleWidget(_:))
        )
        showWidgetItem.state = model.showsWidget ? .on : .off
        menu.addItem(showWidgetItem)

        let refreshItem = item(title: model.isRefreshing ? "Refreshing…" : "Refresh", action: #selector(refresh(_:)))
        refreshItem.isEnabled = !model.isRefreshing
        menu.addItem(refreshItem)

        menu.addItem(item(title: "Settings…", action: #selector(showSettings(_:)), key: ","))

        let updateItem = item(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:))
        )
        updateItem.isEnabled = updateCoordinator.canCheckForUpdates
        menu.addItem(updateItem)

        menu.addItem(.separator())
        menu.addItem(item(title: "Quit Dejavu", action: #selector(quit(_:)), key: "q"))
    }

    private func updateStatusButton() {
        updateStatusButton(
            summary: model.statusItemSummary(
                domainState: model.domainState,
                claudeMetrics: model.claudeMenuBarMetrics,
                showsCodex: model.showsCodexInMenuBar
            )
        )
    }

    private func updateStatusButton(summary: MenuBarSummary) {
        guard let button = statusItem?.button else { return }
        button.image = summary.items.isEmpty
            ? NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Dejavu")
            : nil
        button.title = ""
        button.attributedTitle = makeStatusTitle(summary: summary)
        button.setAccessibilityValue(
            summary.accessibilityTitle.isEmpty
                ? NSLocalizedString("No usage metric shown", comment: "Empty status item")
                : summary.accessibilityTitle
        )
    }

    private func makeStatusTitle(summary: MenuBarSummary) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]

        func appendProviderIcon(_ provider: MenuBarSummary.Item.Provider) {
            if result.length > 0 {
                result.append(NSAttributedString(string: "  ", attributes: textAttributes))
            }
            let imageName = provider == .claude
                ? "ClaudeSparkMenuBar"
                : "CodexMenuBar"
            if let image = NSImage(named: imageName) {
                image.isTemplate = true
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = NSRect(x: 0, y: -2, width: 14, height: 14)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " ", attributes: textAttributes))
            }
        }

        var previousProvider: MenuBarSummary.Item.Provider?
        for item in summary.items {
            if previousProvider != item.provider {
                appendProviderIcon(item.provider)
                previousProvider = item.provider
            } else {
                result.append(NSAttributedString(string: "  ", attributes: textAttributes))
            }
            result.append(NSAttributedString(string: item.value, attributes: textAttributes))
        }
        return result
    }

    private func appendSummary(title: String) {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: "Status menu summary"), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func appendProviderSummary(provider: ProviderBrand, limits: [UsageLimitViewState]) {
        let title = limits.map { "\(NSLocalizedString($0.label, comment: "Usage metric")) \($0.displayText)" }.joined(separator: "  ")
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let image = NSImage(named: provider.assetName) {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            item.image = image
        }

        let attributedTitle = NSMutableAttributedString()
        for (index, limit) in limits.enumerated() {
            if index > 0 {
                attributedTitle.append(NSAttributedString(string: "  "))
            }
            attributedTitle.append(NSAttributedString(
                string: "\(NSLocalizedString(limit.label, comment: "Usage metric")) \(limit.displayText)",
                attributes: [.foregroundColor: NSColor.labelColor]
            ))
        }
        item.attributedTitle = attributedTitle
        item.setAccessibilityLabel("\(provider.rawValue.capitalized) \(title)")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func item(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString(title, comment: "Status menu action"), action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
