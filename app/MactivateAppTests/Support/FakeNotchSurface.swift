import AppKit
import SwiftUI
@testable import MactivateApp

@MainActor
final class FakeNotchSurface: NotchSurfaceControlling {
    var window: NSWindow?
    private(set) var setContentCount = 0
    private(set) var compactCount = 0
    private(set) var expandedCount = 0
    private(set) var hideCount = 0

    func setContent(_ content: AnyView) {
        setContentCount += 1
    }

    func showCompact(on screen: NSScreen) async {
        compactCount += 1
    }

    func showExpanded(on screen: NSScreen, interactive: Bool) async {
        expandedCount += 1
    }

    func hide() async {
        hideCount += 1
    }
}
