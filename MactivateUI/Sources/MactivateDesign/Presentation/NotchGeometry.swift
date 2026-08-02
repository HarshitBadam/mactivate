import Foundation

/// What the UI needs to know about a display, without importing AppKit. The view
/// layer builds one of these from `NSScreen` (frame plus `safeAreaInsets`) so all
/// the arithmetic below stays testable off-Mac.
public struct DisplayDescription: Equatable, Sendable {
    /// Full display bounds in points.
    public var size: CGSize
    /// Notch size in points, or `nil` on a display without one. Derived from
    /// `NSScreen.safeAreaInsets.top` and `auxiliaryTopLeftArea` on Mac.
    public var notchSize: CGSize?
    /// Menu-bar height, so a floating panel on a notchless display can clear it.
    public var menuBarHeight: CGFloat

    public init(size: CGSize, notchSize: CGSize? = nil, menuBarHeight: CGFloat = 24) {
        self.size = size
        self.notchSize = notchSize
        self.menuBarHeight = menuBarHeight
    }

    public var hasNotch: Bool { notchSize != nil }
}

/// Where and how big the notch surface is, in a coordinate space with the origin
/// at the display's top-left and y growing downward. The window layer flips it
/// once, at the boundary, rather than spreading flipped arithmetic around.
public struct NotchPanelLayout: Equatable, Sendable {
    /// Panel rect for the expanded workspace.
    public var panel: CGRect
    /// Rect of the physical notch (or the synthetic pill on a notchless
    /// display), which the panel's top edge wraps around.
    public var notch: CGRect
    /// The pointer region that arms the panel when hand-near sensing is
    /// unavailable: the notch plus a small margin.
    public var hoverZone: CGRect
    /// True when the layout is anchored to a real notch, which is what decides
    /// whether the shape draws notch shoulders or a plain rounded card.
    public var isNotchAttached: Bool
    public var cornerRadius: CGFloat

    public init(
        panel: CGRect,
        notch: CGRect,
        hoverZone: CGRect,
        isNotchAttached: Bool,
        cornerRadius: CGFloat
    ) {
        self.panel = panel
        self.notch = notch
        self.hoverZone = hoverZone
        self.isNotchAttached = isNotchAttached
        self.cornerRadius = cornerRadius
    }
}

/// Sizing for the notch-attached workspace.
///
/// The product asks for "approximately 60% of the screen". That is applied per
/// axis — 60% of width and 60% of height — which is what makes the surface read
/// as a large drop-down over the top-centre of the display rather than a
/// full-screen takeover. The result is clamped so the panel stays usable on a
/// 13-inch built-in display and does not become absurd on a 6K external one.
public enum NotchGeometry {
    public static let defaultCoverage: CGFloat = 0.6

    public static let minimumPanelSize = CGSize(width: 680, height: 420)
    public static let maximumPanelSize = CGSize(width: 1160, height: 760)

    /// Synthetic notch used on displays without one, so the same drop-down
    /// silhouette and animation work everywhere.
    public static let syntheticNotchSize = CGSize(width: 180, height: 6)

    public static func layout(
        for display: DisplayDescription,
        coverage: CGFloat = defaultCoverage
    ) -> NotchPanelLayout {
        let clampedCoverage = min(0.9, max(0.3, coverage))

        let width = clamp(
            display.size.width * clampedCoverage,
            min: min(minimumPanelSize.width, display.size.width - 32),
            max: min(maximumPanelSize.width, display.size.width - 32)
        )
        let height = clamp(
            display.size.height * clampedCoverage,
            min: min(minimumPanelSize.height, display.size.height - 64),
            max: min(maximumPanelSize.height, display.size.height - 64)
        )

        let notchSize = display.notchSize ?? syntheticNotchSize
        // A notchless display cannot tuck the panel under the menu bar, so the
        // panel starts below it and the synthetic notch sits at its top edge.
        let panelTop: CGFloat = display.hasNotch ? 0 : display.menuBarHeight
        let panelOriginX = (display.size.width - width) / 2

        let notchOrigin = CGPoint(
            x: (display.size.width - notchSize.width) / 2,
            y: panelTop
        )

        let notch = CGRect(origin: notchOrigin, size: notchSize)
        let hoverInset: CGFloat = 14

        return NotchPanelLayout(
            panel: CGRect(x: panelOriginX, y: panelTop, width: width, height: height),
            notch: notch,
            hoverZone: notch.insetBy(dx: -hoverInset, dy: -hoverInset),
            isNotchAttached: display.hasNotch,
            cornerRadius: Metrics.Radius.panel
        )
    }

    /// Height of the closed presence: just enough to be a hover target and to
    /// show the "armed" hairline, never enough to compete with the menu bar.
    public static func closedHeight(for display: DisplayDescription) -> CGFloat {
        display.hasNotch ? (display.notchSize?.height ?? syntheticNotchSize.height) : syntheticNotchSize.height
    }

    static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        guard upper > lower else { return max(0, upper) }
        return Swift.min(upper, Swift.max(lower, value))
    }
}
