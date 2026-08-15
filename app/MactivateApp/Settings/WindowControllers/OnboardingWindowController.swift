import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    init(
        state: AppState,
        openSettings: @escaping () -> Void,
        complete: @escaping () -> Void
    ) {
        let hostingController = NSHostingController(
            rootView: OnboardingView(
                state: state,
                openSettings: openSettings,
                complete: complete
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Mactivate"
        window.styleMask = [.titled, .closable]
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
