import AppKit
import MactivateRuntime
import OSLog

struct StatusItemActions {
    let togglePanel: (NSScreen?) -> Void
    let showSettings: () -> Void
    let refreshExternalState: () -> Void
    let setPanelHintsEnabled: (Bool) -> Void
    let setLaunchAtLoginEnabled: (Bool) -> Void
    let quit: () -> Void
}

@MainActor
final class StatusItemController: NSObject {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mactivate.app",
        category: "status-item"
    )
    private let statusItem: NSStatusItem
    private let actions: StatusItemActions
    private var snapshot = RuntimeSnapshot()
    private var configuration = RuntimeConfiguration.default
    private var launchAtLoginStatus: LaunchAtLoginStatus = .disabled

    init(actions: StatusItemActions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        guard let button = statusItem.button else {
            logger.fault("macOS did not provide a status-item button")
            return
        }
        let image = NSImage(
            systemSymbolName: "hand.tap",
            accessibilityDescription: "Mactivate"
        )
        image?.isTemplate = true
        button.image = image
        if image == nil {
            logger.error("The hand.tap symbol is unavailable; using a text fallback")
            button.title = "M"
        }
        button.toolTip = "Mactivate"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Mactivate menu")
        logger.notice("Menu-bar item installed")
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func update(snapshot: RuntimeSnapshot,
                configuration: RuntimeConfiguration,
                launchAtLoginStatus: LaunchAtLoginStatus) {
        self.snapshot = snapshot
        self.configuration = configuration
        self.launchAtLoginStatus = launchAtLoginStatus
    }

    var screen: NSScreen? {
        statusItem.button?.window?.screen
    }

    @objc
    private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            actions.togglePanel(sender.window?.screen)
        }
    }

    private func showContextMenu() {
        actions.refreshExternalState()
        let menu = NSMenu()
        menu.addItem(item(
            title: "Open Panel",
            action: #selector(openPanel)
        ))
        menu.addItem(.separator())

        let tapState = NSMenuItem(
            title: tapStatusTitle,
            action: nil,
            keyEquivalent: ""
        )
        tapState.isEnabled = false
        menu.addItem(tapState)

        let hoverState = NSMenuItem(
            title: hoverStatusTitle,
            action: nil,
            keyEquivalent: ""
        )
        hoverState.isEnabled = false
        menu.addItem(hoverState)

        let hoverToggle = item(
            title: "Experimental Hover",
            action: #selector(togglePanelHints)
        )
        hoverToggle.state = configuration.panelHintsEnabled ? .on : .off
        menu.addItem(hoverToggle)

        let loginToggle = item(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin)
        )
        loginToggle.state = launchAtLoginStatus.isRegistered ? .on : .off
        menu.addItem(loginToggle)

        menu.addItem(.separator())
        menu.addItem(item(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
        menu.addItem(item(
            title: "Quit Mactivate",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(title: String,
                      action: Selector,
                      keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = self
        return item
    }

    private var tapStatusTitle: String {
        switch snapshot.tap {
        case .inactive:
            return "Palm taps: off"
        case .warmingUp:
            return "Palm taps: warming up"
        case .available:
            return "Palm taps: ready"
        case .unavailable:
            return "Palm taps: unavailable"
        }
    }

    private var hoverStatusTitle: String {
        switch snapshot.panelHint {
        case .inactive:
            return "Experimental hover: off"
        case .disabled:
            return "Experimental hover: disabled"
        case .warmingUp:
            return "Experimental hover: warming up"
        case .available:
            return "Experimental hover: ready"
        case .tooDim:
            return "Experimental hover: too dim"
        case .unavailable:
            return "Experimental hover: unavailable"
        }
    }

    @objc private func openPanel() {
        actions.togglePanel(screen)
    }

    @objc private func openSettings() {
        actions.showSettings()
    }

    @objc private func togglePanelHints() {
        actions.setPanelHintsEnabled(!configuration.panelHintsEnabled)
    }

    @objc private func toggleLaunchAtLogin() {
        actions.setLaunchAtLoginEnabled(!launchAtLoginStatus.isRegistered)
    }

    @objc private func quit() {
        actions.quit()
    }
}
