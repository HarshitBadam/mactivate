import Foundation

/// Layout constants for every Mactivate surface.
///
/// The values follow AppKit/SwiftUI conventions rather than inventing a scale:
/// an 8-point rhythm with 4-point half steps, 20-point window margins matching
/// System Settings' form insets, and control heights that match stock AppKit
/// controls so Mactivate's surfaces sit next to system UI without looking
/// slightly off.
public enum Metrics {
    /// 8-point rhythm with 4-point half steps.
    public enum Spacing {
        public static let hairline: CGFloat = 2
        public static let tight: CGFloat = 4
        public static let snug: CGFloat = 8
        public static let regular: CGFloat = 12
        public static let roomy: CGFloat = 16
        public static let section: CGFloat = 24
        public static let major: CGFloat = 32
    }

    /// Continuous-corner radii. `panel` matches the notch panel's own shell;
    /// `card` and `control` match stock grouped-form and button geometry.
    public enum Radius {
        public static let control: CGFloat = 6
        public static let chip: CGFloat = 8
        public static let card: CGFloat = 12
        public static let panel: CGFloat = 20
        public static let pad: CGFloat = 14
    }

    public enum Control {
        public static let rowHeight: CGFloat = 28
        public static let padMinSide: CGFloat = 72
        public static let hitTargetMinSide: CGFloat = 28
        public static let borderWidth: CGFloat = 1
        public static let focusRingWidth: CGFloat = 3
    }

    public enum Window {
        public static let formMargin: CGFloat = 20
        public static let sidebarMinWidth: CGFloat = 208
        public static let sidebarIdealWidth: CGFloat = 232
        public static let detailMinWidth: CGFloat = 620
        public static let minHeight: CGFloat = 560
        public static let idealWidth: CGFloat = 940
        public static let idealHeight: CGFloat = 660
    }

    public enum Waveform {
        public static let compactHeight: CGFloat = 44
        public static let expandedHeight: CGFloat = 120
        public static let lineWidth: CGFloat = 1.5
    }
}
