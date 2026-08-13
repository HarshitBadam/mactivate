import CoreGraphics
import XCTest
@testable import MactivateApp

final class NotchGeometryTests: XCTestCase {
    func testNotchPanelAnchorsBetweenAuxiliaryAreas() {
        let screen = ScreenDescriptor(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
            visibleFrame: CGRect(x: 0, y: 24, width: 1470, height: 908),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 924, width: 680, height: 32),
            auxiliaryTopRightArea: CGRect(x: 790, y: 924, width: 680, height: 32),
            isBuiltIn: true
        )

        let frame = NotchGeometry.panelFrame(
            on: screen,
            panelSize: CGSize(width: 388, height: 292)
        )

        XCTAssertEqual(frame.midX, 735, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 924, accuracy: 0.001)
    }

    func testNonNotchPanelUsesVisibleTopAndGlobalCoordinates() {
        let screen = ScreenDescriptor(
            displayID: 2,
            frame: CGRect(x: -1920, y: 120, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -1920, y: 120, width: 1920, height: 1056),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )

        let frame = NotchGeometry.panelFrame(
            on: screen,
            panelSize: CGSize(width: 388, height: 292)
        )

        XCTAssertEqual(frame.midX, -960, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 1176, accuracy: 0.001)
    }

    func testPanelIsClampedInsideNarrowScreen() {
        let screen = ScreenDescriptor(
            displayID: 3,
            frame: CGRect(x: 400, y: 0, width: 320, height: 800),
            visibleFrame: CGRect(x: 400, y: 0, width: 320, height: 776),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            isBuiltIn: false
        )

        let frame = NotchGeometry.panelFrame(
            on: screen,
            panelSize: CGSize(width: 280, height: 200)
        )

        XCTAssertGreaterThanOrEqual(frame.minX, screen.frame.minX + 8)
        XCTAssertLessThanOrEqual(frame.maxX, screen.frame.maxX - 8)
    }
}
