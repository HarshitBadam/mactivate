import XCTest
@testable import MactivateDesign

final class PanelPresentationTests: XCTestCase {
    func testHandWaveOpensWithoutTakingFocus() {
        var panel = PanelPresentation()
        panel.handle(.handNearBegan)
        XCTAssertEqual(panel.state, .armed)
        XCTAssertFalse(panel.acceptsPointerInput, "An armed panel must stay click-through.")

        panel.handle(.handNearResolved)
        XCTAssertEqual(panel.state, .open(reason: .handNear))
        XCTAssertFalse(panel.shouldActivateApp, "A physical trigger must never steal focus.")
        XCTAssertTrue(panel.acceptsPointerInput)
    }

    func testArmingWithoutResolutionRetracts() {
        var panel = PanelPresentation()
        panel.handle(.handNearBegan)
        panel.handle(.handNearEnded)
        XCTAssertEqual(panel.state, .closed)
    }

    func testHandLeavingArmsAutoDismissRatherThanClosingImmediately() {
        var panel = PanelPresentation()
        panel.handle(.handNearResolved)
        panel.handle(.handNearEnded)

        XCTAssertTrue(panel.isExpanded, "The panel must stay readable after the hand leaves.")
        XCTAssertTrue(panel.isAutoDismissArmed)

        panel.handle(.autoDismissElapsed)
        XCTAssertEqual(panel.state, .closed)
    }

    func testInteractionHoldsThePanelOpenThroughAnAutoDismissTick() {
        var panel = PanelPresentation()
        panel.handle(.handNearResolved)
        panel.handle(.handNearEnded)
        panel.handle(.pointerEnteredPanel)

        XCTAssertEqual(panel.state, .held(reason: .handNear))
        XCTAssertFalse(panel.isAutoDismissArmed)

        panel.handle(.autoDismissElapsed)
        XCTAssertTrue(panel.isExpanded, "A held panel must not retract mid-edit.")
    }

    func testEditingDuringAnOpenPanelSurvivesTheHandLeaving() {
        var panel = PanelPresentation()
        panel.handle(.handNearResolved)
        panel.handle(.userInteracted)
        panel.handle(.handNearEnded)
        panel.handle(.autoDismissElapsed)
        XCTAssertTrue(panel.isExpanded)
    }

    func testMenuBarIsTheOnlyEntryPointThatActivatesTheApp() {
        var fromMenuBar = PanelPresentation()
        fromMenuBar.handle(.menuBarOpenRequested)
        XCTAssertTrue(fromMenuBar.shouldActivateApp)

        var fromHotkey = PanelPresentation()
        fromHotkey.handle(.hotkeyPressed)
        XCTAssertTrue(fromHotkey.isExpanded)
        XCTAssertFalse(fromHotkey.shouldActivateApp)
    }

    func testHotkeyTogglesTheOpenPanelClosed() {
        var panel = PanelPresentation()
        panel.handle(.hotkeyPressed)
        panel.handle(.hotkeyPressed)
        XCTAssertEqual(panel.state, .closed)
    }

    func testEscapeAndDisplayChangesReturnToAKnownClosedState() {
        var dismissed = PanelPresentation()
        dismissed.handle(.menuBarOpenRequested)
        dismissed.handle(.dismissRequested)
        XCTAssertEqual(dismissed.state, .closed)

        var reconfigured = PanelPresentation()
        reconfigured.handle(.menuBarOpenRequested)
        reconfigured.handle(.environmentChanged)
        XCTAssertEqual(reconfigured.state, .closed)
        XCTAssertFalse(reconfigured.isAutoDismissArmed)
    }

    func testRepeatedHandNearWhileOpenDoesNotReopenOrRetrigger() {
        var panel = PanelPresentation()
        panel.handle(.handNearResolved)
        panel.handle(.userInteracted)
        panel.handle(.handNearResolved)
        XCTAssertEqual(panel.state, .held(reason: .handNear))
    }

    func testPointerHoverArmsThePanelWhenSensorsAreUnavailable() {
        var panel = PanelPresentation()
        panel.handle(.pointerEnteredHoverZone)
        XCTAssertEqual(panel.state, .armed)
        panel.handle(.userInteracted)
        XCTAssertEqual(panel.state, .held(reason: .pointer))
    }
}
