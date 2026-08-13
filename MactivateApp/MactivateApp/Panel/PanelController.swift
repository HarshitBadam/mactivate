import AppKit
import SwiftUI

enum PanelPresentationMode: Equatable {
    case closed
    case passiveHint
    case interactive
}

final class PanelWindow: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class PanelController {
    private let panelSize = CGSize(width: 388, height: 292)
    private let passiveDuration: TimeInterval = 4
    private let ambientCooldown: TimeInterval = 3
    private let panel: PanelWindow
    private let hostingView: FirstMouseHostingView
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var passiveDismissWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var ambientNotBefore = Date.distantPast
    private var openedFromAmbient = false
    private var targetDisplayID: CGDirectDisplayID?
    private var presentationGeneration: UInt64 = 0

    private(set) var mode: PanelPresentationMode = .closed

    init() {
        panel = PanelWindow(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hostingView = FirstMouseHostingView(rootView: AnyView(EmptyView()))

        panel.contentView = hostingView
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.onCancel = { [weak self] in self?.dismiss() }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenConfigurationChanged()
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.mode == .interactive else { return }
                self?.dismiss()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }

    func setRootView(_ view: AnyView) {
        hostingView.rootView = view
    }

    func showPassiveHint() {
        guard Date() >= ambientNotBefore else { return }
        guard let screen = NSScreen.screens.first(where: {
            $0.mactivateDescriptor?.isBuiltIn == true
        }) else {
            return
        }
        if mode != .closed {
            schedulePassiveDismissIfNeeded()
            return
        }
        present(on: screen, as: .passiveHint)
    }

    func showInteractive(on screen: NSScreen? = nil) {
        passiveDismissWorkItem?.cancel()
        passiveDismissWorkItem = nil

        if mode == .passiveHint {
            mode = .interactive
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let target = screen ?? screenUnderPointer() ?? NSScreen.main
        guard let target else { return }
        if mode == .interactive {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            present(on: target, as: .interactive)
        }
    }

    func toggleInteractive(on screen: NSScreen? = nil) {
        if mode == .interactive {
            dismiss()
        } else {
            showInteractive(on: screen)
        }
    }

    func dismiss() {
        guard mode != .closed else { return }
        presentationGeneration &+= 1
        let dismissGeneration = presentationGeneration
        if openedFromAmbient {
            ambientNotBefore = Date().addingTimeInterval(ambientCooldown)
        }
        mode = .closed
        openedFromAmbient = false
        targetDisplayID = nil
        passiveDismissWorkItem?.cancel()
        passiveDismissWorkItem = nil
        removeEventMonitors()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.mode == .closed,
                      self.presentationGeneration == dismissGeneration else {
                    return
                }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    func closeForSleep() {
        dismiss()
    }

    private func present(on screen: NSScreen, as newMode: PanelPresentationMode) {
        guard let descriptor = screen.mactivateDescriptor else { return }
        presentationGeneration &+= 1
        targetDisplayID = descriptor.displayID
        mode = newMode
        openedFromAmbient = newMode == .passiveHint
        let finalFrame = NotchGeometry.panelFrame(
            on: descriptor,
            panelSize: panelSize
        )
        panel.setFrame(finalFrame, display: true)
        installEventMonitors()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            panel.alphaValue = 1
            orderPanel(for: newMode)
        } else {
            var startFrame = finalFrame
            startFrame.origin.y += 8
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0
            orderPanel(for: newMode)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(
                    name: .easeOut
                )
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        schedulePassiveDismissIfNeeded()
    }

    private func orderPanel(for mode: PanelPresentationMode) {
        switch mode {
        case .closed:
            break
        case .passiveHint:
            panel.orderFrontRegardless()
        case .interactive:
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func schedulePassiveDismissIfNeeded() {
        guard mode == .passiveHint else { return }
        passiveDismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard self?.mode == .passiveHint else { return }
            self?.dismiss()
        }
        passiveDismissWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + passiveDuration,
            execute: item
        )
    }

    private func installEventMonitors() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.window === self.panel {
                if self.mode == .passiveHint {
                    self.mode = .interactive
                    self.passiveDismissWorkItem?.cancel()
                    self.passiveDismissWorkItem = nil
                    NSApp.activate(ignoringOtherApps: true)
                    self.panel.makeKey()
                }
            } else if event.window?.level != .statusBar {
                self.dismiss()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self,
                  self.mode != .closed,
                  !self.panel.frame.contains(NSEvent.mouseLocation) else {
                return
            }
            self.dismiss()
        }
    }

    private func removeEventMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func screenConfigurationChanged() {
        guard mode != .closed,
              let targetDisplayID,
              let screen = NSScreen.screens.first(where: {
                  $0.mactivateDescriptor?.displayID == targetDisplayID
              }),
              let descriptor = screen.mactivateDescriptor else {
            dismiss()
            return
        }
        panel.setFrame(
            NotchGeometry.panelFrame(on: descriptor, panelSize: panelSize),
            display: true,
            animate: false
        )
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
