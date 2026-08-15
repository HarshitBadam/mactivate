import Dispatch
import Foundation

extension MactivateRuntimeController {
    func publishSnapshotIfChanged() {
        guard snapshot != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = snapshot
        emit(.statusChanged(snapshot))
    }

    func emit(_ output: RuntimeOutput) {
        deliveryQueue.async { [outputHandler] in
            outputHandler(output)
        }
    }

    func withRuntimeQueue<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try runtimeQueue.sync(execute: body)
    }

    func startLifecycleMonitoringLocked() {
        guard !monitoringLifecycle else { return }
        monitoringLifecycle = true
        lifecycleMonitor.start(
            onSleep: { [weak self] in self?.handleSystemSleep() },
            onWake: { [weak self] in self?.handleSystemWake() }
        )
    }

    func stopLifecycleMonitoringLocked() {
        guard monitoringLifecycle else { return }
        monitoringLifecycle = false
        lifecycleMonitor.stop()
    }

    func handleSystemSleep() {
        withRuntimeQueue {
            guard snapshot.lifecycle == .running else {
                wasActiveBeforeSleep = false
                return
            }
            wasActiveBeforeSleep = true
            suspendLocked()
        }
    }

    func handleSystemWake() {
        withRuntimeQueue {
            guard wasActiveBeforeSleep else { return }
            wasActiveBeforeSleep = false
            resumeLocked()
        }
    }
}
