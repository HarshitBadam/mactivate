import XCTest
@testable import MactivateDesign

final class NotchGeometryTests: XCTestCase {
    func testPanelTakesRoughlySixtyPercentOfEachAxisAndStaysCentered() {
        let display = DisplayDescription(
            size: CGSize(width: 1512, height: 982),
            notchSize: CGSize(width: 200, height: 32),
            menuBarHeight: 32
        )
        let layout = NotchGeometry.layout(for: display)

        XCTAssertEqual(layout.panel.width, 1512 * 0.6, accuracy: 0.5)
        XCTAssertEqual(layout.panel.height, 982 * 0.6, accuracy: 0.5)
        XCTAssertEqual(layout.panel.midX, display.size.width / 2, accuracy: 0.5)
        XCTAssertEqual(layout.notch.midX, display.size.width / 2, accuracy: 0.5)
        XCTAssertTrue(layout.isNotchAttached)
    }

    func testNotchedPanelHangsFromTheVeryTopEdge() {
        let layout = NotchGeometry.layout(for: PreviewFixtures.display)
        XCTAssertEqual(layout.panel.minY, 0)
        XCTAssertEqual(layout.notch.minY, 0)
    }

    func testNotchlessDisplayClearsTheMenuBarAndUsesASyntheticNotch() {
        let display = DisplayDescription(
            size: CGSize(width: 2560, height: 1440),
            notchSize: nil,
            menuBarHeight: 24
        )
        let layout = NotchGeometry.layout(for: display)

        XCTAssertFalse(layout.isNotchAttached)
        XCTAssertEqual(layout.panel.minY, 24)
        XCTAssertEqual(layout.notch.minY, 24)
        XCTAssertEqual(layout.notch.size, NotchGeometry.syntheticNotchSize)
    }

    func testPanelIsClampedOnVeryLargeAndVerySmallDisplays() {
        let huge = NotchGeometry.layout(
            for: DisplayDescription(size: CGSize(width: 6016, height: 3384))
        )
        XCTAssertEqual(huge.panel.width, NotchGeometry.maximumPanelSize.width)
        XCTAssertEqual(huge.panel.height, NotchGeometry.maximumPanelSize.height)

        let small = NotchGeometry.layout(
            for: DisplayDescription(size: CGSize(width: 1000, height: 600))
        )
        XCTAssertEqual(small.panel.width, NotchGeometry.minimumPanelSize.width)
        XCTAssertEqual(small.panel.height, NotchGeometry.minimumPanelSize.height)

        // A 13-inch built-in display lands between the bounds and gets the
        // proportional size rather than a clamp.
        let laptop = NotchGeometry.layout(
            for: DisplayDescription(size: CGSize(width: 1280, height: 800))
        )
        XCTAssertEqual(laptop.panel.width, 768, accuracy: 0.5)
        XCTAssertEqual(laptop.panel.height, 480, accuracy: 0.5)
    }

    func testPanelNeverExceedsTheDisplayEvenWhenTheMinimumWouldNotFit() {
        let tiny = NotchGeometry.layout(
            for: DisplayDescription(size: CGSize(width: 640, height: 400))
        )
        XCTAssertLessThanOrEqual(tiny.panel.width, 640)
        XCTAssertLessThanOrEqual(tiny.panel.height, 400)
        XCTAssertGreaterThanOrEqual(tiny.panel.minX, 0)
    }

    func testHoverZoneSurroundsTheNotch() {
        let layout = NotchGeometry.layout(for: PreviewFixtures.display)
        XCTAssertTrue(layout.hoverZone.contains(CGPoint(x: layout.notch.midX, y: layout.notch.midY)))
        XCTAssertGreaterThan(layout.hoverZone.width, layout.notch.width)
        XCTAssertGreaterThan(layout.hoverZone.height, layout.notch.height)
    }
}
