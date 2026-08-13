import AppKit
import DynamicNotchKit
import SwiftUI

enum PanelPresentationMode: Equatable {
    case closed
    case passiveHint
    case interactive
}

@MainActor
protocol NotchSurfaceControlling: AnyObject {
    var window: NSWindow? { get }
    func setContent(_ content: AnyView)
    func showCompact(on screen: NSScreen) async
    func showExpanded(on screen: NSScreen, interactive: Bool) async
    func hide() async
}

/// Keeps the package API isolated from the rest of the application.
@MainActor
final class NotchSurfaceController: NotchSurfaceControlling {
    private typealias Surface = DynamicNotch<AnyView, AnyView, AnyView>
    private var surface: Surface?

    var window: NSWindow? { surface?.windowController?.window }

    func setContent(_ content: AnyView) {
        let compactLeading = AnyView(
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
        )
        let compactTrailing = AnyView(EmptyView())
        let surface = Surface(
            hoverBehavior: [.keepVisible, .hapticFeedback, .increaseShadow],
            style: .auto,
            expanded: { content },
            compactLeading: { compactLeading },
            compactTrailing: { compactTrailing }
        )
        surface.transitionConfiguration = transitionConfiguration
        self.surface = surface
    }

    func showCompact(on screen: NSScreen) async {
        guard let surface else { return }
        surface.transitionConfiguration = transitionConfiguration
        let presentation = Task { await surface.compact(on: screen) }
        await Task.yield()
        configureWindow(interactive: false)
        await presentation.value
        configureWindow(interactive: false)
    }

    func showExpanded(on screen: NSScreen, interactive: Bool) async {
        guard let surface else { return }
        surface.transitionConfiguration = transitionConfiguration
        let presentation = Task { await surface.expand(on: screen) }
        await Task.yield()
        configureWindow(interactive: interactive)
        await presentation.value
        configureWindow(interactive: interactive)
    }

    func hide() async {
        await surface?.hide()
    }

    private var transitionConfiguration: DynamicNotchTransitionConfiguration {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return DynamicNotchTransitionConfiguration(
                openingAnimation: .linear(duration: 0.01),
                closingAnimation: .linear(duration: 0.01),
                conversionAnimation: .linear(duration: 0.01),
                skipIntermediateHides: true
            )
        }
        return DynamicNotchTransitionConfiguration(
            openingAnimation: .spring(duration: 0.38, bounce: 0.26),
            closingAnimation: .smooth(duration: 0.24),
            conversionAnimation: .spring(duration: 0.34, bounce: 0.22),
            skipIntermediateHides: true
        )
    }

    private func configureWindow(interactive: Bool) {
        guard let window else { return }
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.level = .screenSaver
        window.hidesOnDeactivate = false
        if interactive {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}

@MainActor
final class PanelController {
    private let panelSize = CGSize(width: 388, height: 276)
    private let passiveDuration: TimeInterval = 4
    private let ambientCooldown: TimeInterval = 3
    private let surface: any NotchSurfaceControlling

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var passiveDismissWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var ambientNotBefore = Date.distantPast
    private var openedFromAmbient = false
    private var targetDisplayID: CGDirectDisplayID?
    private var targetDescriptor: ScreenDescriptor?
    private var presentationGeneration: UInt64 = 0
    private var transitionTask: Task<Void, Never>?

    private(set) var mode: PanelPresentationMode = .closed

    init(surface: (any NotchSurfaceControlling)? = nil) {
        self.surface = surface ?? NotchSurfaceController()
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
        transitionTask?.cancel()
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
        surface.setContent(view)
    }

    func showPassiveHint() {
        guard Date() >= ambientNotBefore else { return }
        guard let screen = NSScreen.screens.first(where: {
            $0.mactivateDescriptor?.isBuiltIn == true &&
                $0.mactivateDescriptor?.hasNotch == true
        }) else {
            return
        }
        if mode == .passiveHint {
            schedulePassiveDismissIfNeeded()
            return
        }
        if mode == .interactive { return }
        present(on: screen, as: .passiveHint)
    }

    func showInteractive(on screen: NSScreen? = nil) {
        passiveDismissWorkItem?.cancel()
        passiveDismissWorkItem = nil
        let target = screen ?? screenUnderPointer() ?? NSScreen.main
        guard let target else { return }
        if mode == .interactive {
            NSApp.activate(ignoringOtherApps: true)
            surface.window?.makeKeyAndOrderFront(nil)
            return
        }
        present(on: target, as: .interactive)
    }

    func toggleInteractive(on screen: NSScreen? = nil) {
        mode == .interactive ? dismiss() : showInteractive(on: screen)
    }

    func dismiss() {
        guard mode != .closed else { return }
        presentationGeneration &+= 1
        transitionTask?.cancel()
        if openedFromAmbient {
            ambientNotBefore = Date().addingTimeInterval(ambientCooldown)
        }
        mode = .closed
        openedFromAmbient = false
        targetDisplayID = nil
        targetDescriptor = nil
        passiveDismissWorkItem?.cancel()
        passiveDismissWorkItem = nil
        removeEventMonitors()
        transitionTask = Task { [surface] in
            await surface.hide()
        }
    }

    func closeForSleep() {
        dismiss()
    }

    private func present(
        on screen: NSScreen,
        as newMode: PanelPresentationMode
    ) {
        guard let descriptor = screen.mactivateDescriptor else { return }
        presentationGeneration &+= 1
        let generation = presentationGeneration
        transitionTask?.cancel()
        targetDisplayID = descriptor.displayID
        targetDescriptor = descriptor
        mode = newMode
        openedFromAmbient = newMode == .passiveHint
        installEventMonitors()

        if newMode == .interactive {
            NSApp.activate(ignoringOtherApps: true)
        }
        transitionTask = Task { [weak self, surface] in
            switch newMode {
            case .closed:
                return
            case .passiveHint:
                await surface.showExpanded(on: screen, interactive: false)
            case .interactive:
                await surface.showExpanded(on: screen, interactive: true)
            }
            guard !Task.isCancelled,
                  self?.presentationGeneration == generation else {
                return
            }
        }
        schedulePassiveDismissIfNeeded()
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
            if event.window === self.surface.window {
                if self.mode == .passiveHint {
                    self.showInteractive(on: self.screenForTargetDisplay())
                }
            } else if event.window?.level != .screenSaver {
                self.dismiss()
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.mode != .closed else { return }
            guard let descriptor = self.targetDescriptor else {
                self.dismiss()
                return
            }
            let interactiveFrame = NotchGeometry.panelFrame(
                on: descriptor,
                panelSize: self.panelSize
            )
            if !interactiveFrame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
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
              screenForTargetDisplay() != nil else {
            dismiss()
            return
        }
    }

    private func screenForTargetDisplay() -> NSScreen? {
        guard let targetDisplayID else { return nil }
        return NSScreen.screens.first {
            $0.mactivateDescriptor?.displayID == targetDisplayID
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(location) }
    }
}
