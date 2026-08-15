import AppKit
import Foundation

public protocol RuntimeLifecycleMonitoring: AnyObject {
    func start(onSleep: @escaping () -> Void,
               onWake: @escaping () -> Void)
    func stop()
}

public final class WorkspaceRuntimeLifecycleMonitor:
    RuntimeLifecycleMonitoring {
    private let notificationCenter: NotificationCenter
    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []

    public init(
        notificationCenter: NotificationCenter =
            NSWorkspace.shared.notificationCenter
    ) {
        self.notificationCenter = notificationCenter
    }

    deinit {
        stop()
    }

    public func start(onSleep: @escaping () -> Void,
                      onWake: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard observers.isEmpty else { return }
        observers = [
            notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: nil
            ) { _ in onSleep() },
            notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: nil
            ) { _ in onWake() }
        ]
    }

    public func stop() {
        let currentObservers: [NSObjectProtocol]
        lock.lock()
        currentObservers = observers
        observers.removeAll()
        lock.unlock()
        for observer in currentObservers {
            notificationCenter.removeObserver(observer)
        }
    }
}
