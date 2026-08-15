import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(state: AppState, actions: SettingsActions) {
        let hostingController = NSHostingController(
            rootView: SettingsView(state: state, actions: actions)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Mactivate Settings"
        window.styleMask = [
            .titled,
            .closable,
            .resizable,
            .fullSizeContentView
        ]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 650)
        window.setContentSize(NSSize(width: 960, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
