import AppKit
import OSLog

@main
enum MactivateApplication {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mactivate.app",
        category: "launch"
    )
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.notice("Application finished launching")
        guard ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath"
        ] == nil else {
            logger.debug("Skipping app UI in the XCTest host")
            return
        }

        do {
            let coordinator = try AppCoordinator()
            self.coordinator = coordinator
            logger.notice("Coordinator and menu-bar item created")
            coordinator.start()
            logger.notice("Runtime startup requested")
        } catch {
            logger.fault(
                "Fatal startup error: \(error.localizedDescription, privacy: .public)"
            )
            presentFatalStartupError(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        coordinator?.reopen()
        return false
    }

    private func presentFatalStartupError(_ error: Error) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Mactivate could not start"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
