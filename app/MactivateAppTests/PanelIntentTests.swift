import AppKit
import MactivateRuntime
import SwiftUI
import XCTest
@testable import MactivateApp

@MainActor
final class PanelIntentTests: XCTestCase {
    func testPanelLifecycleUsesNotchSurfaceAdapter() async throws {
        let surface = FakeNotchSurface()
        let controller = PanelController(surface: surface)
        let screen = try XCTUnwrap(NSScreen.main)

        controller.setRootView(AnyView(Text("Panel")))
        controller.showInteractive(on: screen)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.setContentCount, 1)
        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(controller.mode, .interactive)

        controller.dismiss()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.hideCount, 1)
        XCTAssertEqual(controller.mode, .closed)
    }

    func testPassiveHintExpandsInOneSurfaceTransition() async throws {
        guard NSScreen.screens.contains(where: {
            $0.mactivateDescriptor?.isBuiltIn == true &&
                $0.mactivateDescriptor?.hasNotch == true
        }) else {
            throw XCTSkip("requires a built-in notched display")
        }
        let surface = FakeNotchSurface()
        let controller = PanelController(surface: surface)

        controller.showPassiveHint()
        for _ in 0..<6 {
            await Task.yield()
        }

        XCTAssertEqual(surface.compactCount, 0)
        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(controller.mode, .passiveHint)
        controller.dismiss()
    }

    func testTapIntentForShowPanelExpandsNotchSurface() async {
        let runtime = FakeRuntime()
        let surface = FakeNotchSurface()
        let panelController = PanelController(surface: surface)
        let coordinator = makeCoordinator(
            runtime: runtime,
            panelController: panelController
        )
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "show-panel"
            ),
            gesture: .leftDouble,
            sensorTimestamp: 1,
            regionProfileVersion: "personal-region-test"
        )

        runtime.outputHandler?(.intent(.performAction(
            id: AppActionDefinition.showPanel.id,
            trigger: trigger
        )))
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(surface.expandedCount, 1)
        XCTAssertEqual(panelController.mode, .interactive)
        panelController.dismiss()
    }

    func testUnknownActionIdentifierFailsClosedWithoutExecuting() {
        let runtime = FakeRuntime()
        let coordinator = makeCoordinator(runtime: runtime)
        let trigger = TapTrigger(
            eventID: RuntimeEventID(
                sessionID: UUID(),
                classifierEventID: "tap-1"
            ),
            gesture: .leftDouble,
            sensorTimestamp: 1,
            regionProfileVersion: "personal-region-test"
        )

        runtime.outputHandler?(.intent(.performAction(
            id: "action.does-not-exist",
            trigger: trigger
        )))

        XCTAssertNotNil(coordinator.state.actionError)
    }
}
