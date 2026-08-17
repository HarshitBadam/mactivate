import AppKit
import DynamicNotchKit
import SwiftUI

@MainActor
protocol NotchSurfaceControlling: AnyObject {
    var window: NSWindow? { get }
    func setContent(_ content: AnyView)
    func showCompact(on screen: NSScreen) async
    func showExpanded(on screen: NSScreen, interactive: Bool) async
    func hide() async
}

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
            hoverBehavior: [.hapticFeedback, .increaseShadow],
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
